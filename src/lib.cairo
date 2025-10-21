//! Dynamic world factory configured through dojo models.
//mod lib2;

use starknet::{ClassHash, ContractAddress};

/// Additional config that could be passed to the factory to configure the deployed world.
#[derive(Serde, Drop, Introspect, DojoStore)]
pub struct WorldConfig {
    pub param1: felt252,
    pub param2: felt252,
}

/// Model to store the world reference of a deployed world
/// by the factory.
///
/// Using a Torii to index the factory world will provide
/// the world reference for each deployed world.
#[dojo::model]
pub struct WorldReference {
    #[key]
    pub name: felt252,
    pub address: ContractAddress,
    pub block_number: u64,
    pub tx_hash: felt252,
    pub config: WorldConfig,
    // Can extend with the account triggering the tx, etc...
}

/// This is an alternative way to configure the factory.
/// By using this model, the factory doesn't have to be re-deployed to change the configuration.
/// It's not optimal to have arrays in the model, but if you don't have too much contracts, models, and events,
/// it will be just fine with this.
/// If you expected a large number of contracts, models, and events, then you should split this FactoryConfig into multiple models
/// and keeping counters of each to correctly use the keys.
#[dojo::model]
pub struct FactoryConfig {
    #[key]
    pub version: felt252,
    pub world_class_hash: ClassHash,
    pub default_namespace: ByteArray,
    /// Contracts to be registered (and must be declared before).
    /// (selector, class_hash, init_args)
    pub contracts: Array<(felt252, ClassHash, Array<felt252>)>,
    pub models: Array<ClassHash>,
    pub events: Array<ClassHash>,
}

/// Interface for the world factory.
#[starknet::interface]
pub trait IWorldFactory<T> {
    /// Deploys a new world and returns its address.
    ///
    /// # Arguments
    ///
    /// * `name` - The name of the world.
    /// * `config` - The configuration of the world.
    fn deploy(ref self: T, name: felt252, factory_config_version: felt252, world_config: WorldConfig);

    /// Sets the configuration of the factory.
    ///
    /// # Arguments
    ///
    /// * `config` - The configuration of the factory.
    fn set_config(ref self: T, config: FactoryConfig);
}

#[dojo::contract]
pub mod factory {
    use core::dict::Felt252Dict;
    use dojo::model::ModelStorage;
    use dojo::utils::bytearray_hash;
    use dojo::world::{IWorldDispatcher, IWorldDispatcherTrait};
    use starknet::SyscallResultTrait;
    use super::*;

    #[abi(embed_v0)]
    impl IWorldFactoryImpl of IWorldFactory<ContractState> {
        fn set_config(ref self: ContractState, config: FactoryConfig) {
            let mut factory_world = self.world_default();
            factory_world.write_model(@config);
        }

        fn deploy(ref self: ContractState, name: felt252, factory_config_version: felt252, world_config: WorldConfig) {
            let mut factory_world = self.world_default();
            let factory_config: FactoryConfig = factory_world.read_model(factory_config_version);

            let deployed_world = self.deploy_world(name, factory_config.world_class_hash);

            // Register a default namespace in the new world which is permissionless.
            deployed_world.register_namespace(factory_config.default_namespace.clone());

            // A mapping of the dojo selector of a contract to its address (in felt252) since we
            // can't use the ContractAddress type.
            let mut dojo_contracts_addresses: Felt252Dict<felt252> = Default::default();

            // Register the contracts in the new world, and keep the addresses in a felt252dict
            // mapped to the selector.
            for (selector, class_hash, _init_args) in factory_config.contracts.span() {
                let addr = deployed_world
                    .register_contract(*selector, factory_config.default_namespace.clone(), *class_hash);
                dojo_contracts_addresses.insert(*selector, addr.into());
            }

            for class_hash in factory_config.models.span() {
                deployed_world.register_model(factory_config.default_namespace.clone(), *class_hash);
            }

            for class_hash in factory_config.events.span() {
                deployed_world.register_event(factory_config.default_namespace.clone(), *class_hash);
            }

            let namespace_hash = bytearray_hash(@factory_config.default_namespace);

            // Sync permissions. In this case, give writer permission on the default
            // namespace ("game" in this example) to all the provided contracts.
            // Let's say for now we give writer permission to all contracts.
            // we can use a felt252dict to have more fine-grained control.
            for (selector, _, _) in factory_config.contracts.span() {
                let addr = dojo_contracts_addresses.get(*selector);
                deployed_world.grant_writer(namespace_hash, addr.try_into().unwrap());
            }

            // Call the `dojo_init` for each contract. In case the dojo init
            // has parameters, then it will be better using a felt252dict
            // and pass the init arguments to the contract.
            // This example considers all the dojo_init to be without parameters.
            for (selector, _, init_args) in factory_config.contracts.span() {
                let _addr = dojo_contracts_addresses.get(*selector);
                deployed_world.init_contract(*selector, init_args.span());
            }

            // Make any other call as necessary (set the world config for instance).

            let world_ref = WorldReference {
                name: name,
                address: deployed_world.contract_address,
                block_number: starknet::get_block_number(),
                tx_hash: starknet::get_tx_info().transaction_hash,
                config: world_config,
            };

            factory_world.write_model(@world_ref);
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        /// Default world storage for the factory.
        fn world_default(self: @ContractState) -> dojo::world::WorldStorage {
            self.world(@"wf")
        }

        /// Deploys a new world and returns its address.
        fn deploy_world(self: @ContractState, name: felt252, world_class_hash: ClassHash) -> IWorldDispatcher {
            let (world_address, _ctor_result) = starknet::syscalls::deploy_syscall(
                world_class_hash.try_into().unwrap(),
                name,
                [world_class_hash.into()].span(),
                false,
            )
                .unwrap_syscall();

            IWorldDispatcher { contract_address: world_address }
        }
    }
}

#[cfg(test)]
mod tests {}
