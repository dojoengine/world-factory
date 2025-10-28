//! World factory, configured through dojo models.
//!
//! The world factory is a contract that can be used to deploy and manage dojo worlds from the
//! chain.
//! This removes the need of using Sozo for instance and manage the world from a client application
//! directly.
//!
//! Due to the limitation of the transaction resources, the factory is configured through dojo
//! models to support large worlds with multiple transactions.
//! The state is kept internally, so there is no need for external cursors to remember on the client
//! side.

#[dojo::contract]
pub mod factory {
    use core::num::traits::Zero;
    use dojo::model::ModelStorage;
    use dojo::utils::bytearray_hash;
    use dojo::world::{IWorldDispatcher, IWorldDispatcherTrait};
    use starknet::{ClassHash, ContractAddress, SyscallResultTrait};
    use crate::factory_models::{
        FactoryConfig, FactoryConfigContract, FactoryConfigOwner, FactoryDeploymentCursor,
    };
    use crate::interface::IWorldFactory;
    use crate::world_models::{WorldContract, WorldDeployed};

    mod errors {
        pub const DEPLOYMENT_ALREADY_COMPLETED: felt252 = 'deployment already completed';
        pub const NOT_CONFIG_OWNER: felt252 = 'not config owner';
    }

    #[abi(embed_v0)]
    impl IWorldFactoryImpl of IWorldFactory<ContractState> {
        fn set_config(ref self: ContractState, config: FactoryConfig) {
            let mut factory_world = self.world_default();

            let config_owner: FactoryConfigOwner = factory_world.read_model(config.version);

            if config_owner.contract_address.is_non_zero() {
                assert(
                    starknet::get_caller_address() == config_owner.contract_address,
                    errors::NOT_CONFIG_OWNER,
                );
            }

            factory_world
                .write_model(
                    @FactoryConfigOwner {
                        version: config.version, contract_address: starknet::get_caller_address(),
                    },
                );

            factory_world.write_model(@config);
        }

        fn deploy(ref self: ContractState, name: felt252, factory_config_version: felt252) {
            let mut factory_world = self.world_default();
            let factory_config: FactoryConfig = factory_world.read_model(factory_config_version);
            let mut cursor: FactoryDeploymentCursor = factory_world
                .read_model((factory_config_version, name));

            let max_actions = cursor.total_actions + factory_config.max_actions;

            assert(!cursor.completed, errors::DEPLOYMENT_ALREADY_COMPLETED);

            // Deploy the world if not done already.
            //
            let world_class_hash = factory_config.world_class_hash;
            let deployed_world = if let Some(world_address) = cursor.world_address {
                IWorldDispatcher { contract_address: world_address }
            } else {
                let wd = self.deploy_world(name, world_class_hash);
                cursor.world_address = Some(wd.contract_address);

                // Register a default namespace in the new world which is permissionless.
                wd.register_namespace(factory_config.default_namespace.clone());

                factory_world.write_model(@cursor);
                wd
            };

            // Sync contracts.
            //
            // TODO: we can optimize by first comparing the length of the array with the cursor, to
            // avoid iterating for nothing.
            let mut contract_idx: u64 = 0;
            for contract in factory_config.contracts.span() {
                if cursor.contract_cursor > contract_idx {
                    contract_idx += 1;
                    continue;
                }

                let addr = deployed_world
                    .register_contract(
                        *contract.selector,
                        factory_config.default_namespace.clone(),
                        *contract.class_hash,
                    );

                factory_world
                    .write_model(
                        @WorldContract {
                            name, contract_selector: *contract.selector, contract_address: addr,
                        },
                    );

                contract_idx += 1;
                cursor.total_actions += 1;
                cursor.contract_cursor += 1;

                if cursor.total_actions >= max_actions {
                    factory_world.write_model(@cursor);
                    return;
                }
            }

            // Sync models.
            //
            // TODO: we can optimize by first comparing the length of the array with the cursor, to
            // avoid iterating for nothing.
            let mut model_idx: u64 = 0;
            for class_hash in factory_config.models.span() {
                if cursor.model_cursor > model_idx {
                    model_idx += 1;
                    continue;
                }

                deployed_world
                    .register_model(factory_config.default_namespace.clone(), *class_hash);

                model_idx += 1;
                cursor.total_actions += 1;
                cursor.model_cursor += 1;

                if cursor.total_actions >= max_actions {
                    factory_world.write_model(@cursor);
                    return;
                }
            }

            // Sync events.
            //
            // TODO: we can optimize by first comparing the length of the array with the cursor, to
            // avoid iterating for nothing.
            let mut event_idx: u64 = 0;
            for class_hash in factory_config.events.span() {
                if cursor.event_cursor > event_idx {
                    event_idx += 1;
                    continue;
                }

                deployed_world
                    .register_event(factory_config.default_namespace.clone(), *class_hash);

                event_idx += 1;
                cursor.total_actions += 1;
                cursor.event_cursor += 1;

                if cursor.total_actions >= max_actions {
                    factory_world.write_model(@cursor);
                    return;
                }
            }

            let namespace_hash = bytearray_hash(@factory_config.default_namespace);

            // Sync permissions for the contracts.
            //
            let mut permission_idx: u64 = 0;
            for contract in factory_config.contracts.span() {
                if cursor.permission_cursor > permission_idx {
                    permission_idx += 1;
                    continue;
                }

                // Get the address of the contract from the factory world, indexed by the name of
                // the world and the selector of the contract.
                let wc: WorldContract = factory_world.read_model((name, *contract.selector));
                let wc_address: ContractAddress = wc.contract_address;

                // TODO: here, the permission idx is actually set at the contract level, and not at
                // the resource level.
                // So we may have more actions than expected based on the config.
                // We need to adjust that in the future, since currently most people use the factory
                // with the default namespace writer all.
                // However, permissions are very simple calls, so they shouldn't add too much
                // overhead.

                if factory_config.default_namespace_writer_all {
                    deployed_world.grant_writer(namespace_hash, wc_address);
                }

                for resource in contract.writer_of_resources {
                    deployed_world.grant_writer(*resource, wc_address);
                }

                for resource in contract.owner_of_resources {
                    deployed_world.grant_owner(*resource, wc_address);
                }

                permission_idx += 1;
                cursor.total_actions += 1;
                cursor.permission_cursor += 1;

                if cursor.total_actions >= max_actions {
                    factory_world.write_model(@cursor);
                    return;
                }
            }

            // Initialize the dojo contracts.
            //
            let mut init_idx: u64 = 0;
            for contract in factory_config.contracts.span() {
                let contract: FactoryConfigContract = *contract;

                if cursor.init_cursor > init_idx {
                    init_idx += 1;
                    continue;
                }

                let _wc: WorldContract = factory_world.read_model((name, contract.selector));
                deployed_world.init_contract(contract.selector, contract.init_args);

                init_idx += 1;
                cursor.total_actions += 1;
                cursor.init_cursor += 1;

                if cursor.total_actions >= max_actions {
                    factory_world.write_model(@cursor);
                    return;
                }
            }

            let world_ref = WorldDeployed {
                name: name,
                address: deployed_world.contract_address,
                block_number: starknet::get_block_number(),
                tx_hash: starknet::get_tx_info().transaction_hash,
            };

            factory_world.write_model(@world_ref);

            cursor.completed = true;
            factory_world.write_model(@cursor);
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        /// Default world storage for the factory.
        fn world_default(self: @ContractState) -> dojo::world::WorldStorage {
            self.world(@"wf")
        }

        /// Deploys a new world and returns its address.
        fn deploy_world(
            self: @ContractState, name: felt252, world_class_hash: ClassHash,
        ) -> IWorldDispatcher {
            let (world_address, _ctor_result) = starknet::syscalls::deploy_syscall(
                world_class_hash.try_into().unwrap(), name, [world_class_hash.into()].span(), false,
            )
                .unwrap_syscall();

            IWorldDispatcher { contract_address: world_address }
        }
    }
}
