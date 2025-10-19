//! Static world factory configured through constants (need upgrades).

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

/// Interface for the world factory.
#[starknet::interface]
pub trait IWorldFactory<T> {
    /// Deploys a new world and returns its address.
    ///
    /// # Arguments
    ///
    /// * `name` - The name of the world.
    /// * `config` - The configuration of the world.
    fn deploy(ref self: T, name: felt252, config: WorldConfig);
}

/// Currently the world class hash is required, but soon will not be needed anymore.
pub const WORLD_CLASS_HASH_FELT: felt252 =
    0x011c8465be5a0ce5e52e329cbdb1a22d8a76a5a906b4f6d89d515a775082d07a;

/// Define the list of dojo contracts to work with.
pub const CONTRACTS: [(felt252, ClassHash); 3] = [
    (selector_from_tag!("game-c1"), TryInto::<felt252, ClassHash>::try_into(0x1).unwrap()),
    (selector_from_tag!("game-c2"), TryInto::<felt252, ClassHash>::try_into(0x2).unwrap()),
    (selector_from_tag!("game-c3"), TryInto::<felt252, ClassHash>::try_into(0x3).unwrap()),
];

/// Define the models to register in the world. Only the class hash is needed.
pub const MODELS: [ClassHash; 3] = [
    TryInto::<felt252, ClassHash>::try_into(0x4).unwrap(),
    TryInto::<felt252, ClassHash>::try_into(0x5).unwrap(),
    TryInto::<felt252, ClassHash>::try_into(0x6).unwrap(),
];

/// Define the events to register in the world. Only the class hash is needed.
pub const EVENTS: [ClassHash; 3] = [
    TryInto::<felt252, ClassHash>::try_into(0x7).unwrap(),
    TryInto::<felt252, ClassHash>::try_into(0x8).unwrap(),
    TryInto::<felt252, ClassHash>::try_into(0x9).unwrap(),
];

#[dojo::contract]
pub mod factory {
    use core::dict::Felt252Dict;
    use dojo::model::ModelStorage;
    use dojo::utils::bytearray_hash;
    use dojo::world::{IWorldDispatcher, IWorldDispatcherTrait};
    use starknet::{ContractAddress, SyscallResultTrait};
    use super::*;

    #[abi(embed_v0)]
    impl IWorldFactoryImpl of IWorldFactory<ContractState> {
        fn deploy(ref self: ContractState, name: felt252, config: WorldConfig) {
            let mut factory_world = self.world_default();

            let deployed_world_address = self.deploy_world(name);
            let deployed_world = IWorldDispatcher { contract_address: deployed_world_address };

            // Register a default namespace in the new world.
            let namespace: ByteArray = "game";
            let namespace_hash = bytearray_hash!("game");
            deployed_world.register_namespace(namespace.clone());

            // A mapping of the dojo selector of a contract to its address (in felt252) since we
            // can't use the ContractAddress type.
            let mut dojo_contracts_addresses: Felt252Dict<felt252> = Default::default();

            // Register the contracts in the new world, and keep the addresses in a felt252dict
            // mapped to the selector.
            for (selector, class_hash) in CONTRACTS.span() {
                let addr = deployed_world
                    .register_contract(*selector, namespace.clone(), *class_hash);
                dojo_contracts_addresses.insert(*selector, addr.into());
            }

            for class_hash in MODELS.span() {
                deployed_world.register_model(namespace.clone(), *class_hash);
            }

            for class_hash in EVENTS.span() {
                deployed_world.register_event(namespace.clone(), *class_hash);
            }

            // Sync permissions. In this case, give writer permission on the default
            // namespace ("game" in this example) to all the provided contracts.
            // Let's say for now we give writer permission to all contracts.
            // we can use a felt252dict to have more fine-grained control.
            for (selector, _) in CONTRACTS.span() {
                let addr = dojo_contracts_addresses.get(*selector);
                deployed_world.grant_writer(namespace_hash, addr.try_into().unwrap());
            }

            // Call the `dojo_init` for each contract. In case the dojo init
            // has parameters, then it will be better using a felt252dict
            // and pass the init arguments to the contract.
            // This example considers all the dojo_init to be without parameters.
            for (selector, _) in CONTRACTS.span() {
                let addr = dojo_contracts_addresses.get(*selector);
                match starknet::syscalls::call_contract_syscall(
                    addr.try_into().unwrap(), dojo::world::world::DOJO_INIT_SELECTOR, [].span(),
                ) {
                    Ok(_) => {},
                    Err(error) => {
                        panic!(
                            "Failed to call dojo_init for contract {:?} at address {}: {:?}",
                            selector,
                            addr,
                            error,
                        );
                    },
                }
            }

            // Make any other call as necessary (set the world config for instance).

            let world_ref = WorldReference {
                name: name,
                address: deployed_world.contract_address,
                block_number: starknet::get_block_number(),
                tx_hash: starknet::get_tx_info().transaction_hash,
                config: config,
            };

            factory_world.write_model(@world_ref);
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        /// Default world storage for the factory.
        fn world_default(self: @ContractState) -> dojo::world::WorldStorage {
            self.world(@"factory")
        }

        /// Deploys a new world and returns its address.
        fn deploy_world(self: @ContractState, name: felt252) -> ContractAddress {
            let (world_address, _ctor_result) = starknet::syscalls::deploy_syscall(
                WORLD_CLASS_HASH_FELT.try_into().unwrap(),
                name,
                [WORLD_CLASS_HASH_FELT].span(),
                false,
            )
                .unwrap_syscall();

            world_address
        }
    }
}

#[cfg(test)]
mod tests {}
