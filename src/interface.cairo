use crate::factory_models::FactoryConfig;

/// Interface for the world factory.
#[starknet::interface]
pub trait IWorldFactory<T> {
    /// Deploys a new world and returns its address.
    ///
    /// This entrypoint must be called multiple times until the deployment is completed.
    /// To know if the deployment is completed, you can check the `completed` field of the
    /// `FactoryDeploymentCursor` model, or expect a transaction to revert with the error
    /// `DEPLOYMENT_ALREADY_COMPLETED`.
    ///
    /// # Arguments
    ///
    /// * `name` - The name of the world.
    /// * `factory_config_version` - The version of the factory configuration set using the
    /// `set_config` entrypoint.
    fn deploy(ref self: T, name: felt252, factory_config_version: felt252);

    /// Sets the configuration of the factory.
    ///
    /// TODO: currently `FactoryConfig` is a big model, where the 300 felts limit may be reached
    /// for very large worlds. This will need to be split into multiple models to not
    /// limit large worlds for using the factory.
    ///
    /// To ensure that once a config is set, only the writer of the config can edit it,
    /// the factory will check if the caller address is the writer of the config if it is
    /// already set (owner_address being non-zero).
    ///
    /// # Arguments
    ///
    /// * `config` - The configuration of the factory.
    fn set_config(ref self: T, config: FactoryConfig);
}
