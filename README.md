# Dojo world factory

This repo contains a dojo world factory contract that can be used to deploy and manage dojo worlds from the chain.

## How to deploy and configure the factory

To deploy the factory, change the seed in the `dojo_sepolia.toml` file to a new seed, then build and run:
```bash
sozo -P sepolia build

# You can kill sozo migrate once the declaration phase is done.
# sozo will have a new argument to stop automatically after the declaration phase.
sozo -P sepolia migrate
```

To configure the factory, you will want to use the `set_config` entrypoint.
An easy way to get the information for the configuration would be using `sozo inspect` in your Dojo project,
since currently the factory is expecting all the resources class hashes to be declared.

Example of a Dojo starter project:

```
 World  | Contract Address                                                   | Class Hash                                                         
--------+--------------------------------------------------------------------+--------------------------------------------------------------------
 Synced | 0x04b86a3bdf5b6829ad1d3257201c34e12a9874e5580415a8e3ad5b9a714353fe | 0x057994b6a75fad550ca18b41ee82e2110e158c59028c4478109a67965a0e5b1e 

 Namespaces | Status | Dojo Selector                                                      
------------+--------+--------------------------------------------------------------------
 ds         | Synced | 0x05eae07c7d9064bc7fbf83403a0c38168355e202f9768ada3a5b0615f96d3726 

 Contracts  | Status | Is Initialized | Dojo Selector                                                      | Contract Address                                                   
------------+--------+----------------+--------------------------------------------------------------------+--------------------------------------------------------------------
 ds-actions | Synced | true           | 0x051ca47f464277070d0ef7e920eeb1ad3e1554f6264181b7f946fb0a7491564b | 0x07ea0667abebd368339ca0ed3aa397bee189f5e8f6142c8154d342af34c79363 

 Models                 | Status | Dojo Selector                                                      
------------------------+--------+--------------------------------------------------------------------
 ds-DirectionsAvailable | Synced | 0x00d80746894d0c7ae86775f58d6cf850ca67966661561d24bdd3c72e3d66a6c5 
 ds-Moves               | Synced | 0x0479c8d8af3fd4be7d32373f565f5d34f325b156f8ee6a800e7aa48277e001b5 
 ds-Position            | Synced | 0x02ddf9b74b363cb2feb045060539aa7863e78eabaa70d4612751ddcf48702a5f 
 ds-PositionCount       | Synced | 0x05ba0cf4ca39b597382250dc8a55d2b40e7a325f943f46bf5275b4864d061bc1 

 Events   | Status | Dojo Selector                                                      
----------+--------+--------------------------------------------------------------------
 ds-Moved | Synced | 0x060d7ef5ae8f195d4dba9f55b4c61fc055fbc5d5338d30f2072942a4463f0c11
```

The `FactoryConfig` would be something like this:
```rust
let factory_config = FactoryConfig {
    version: '1',
    world_class_hash: 0x057994b6a75fad550ca18b41ee82e2110e158c59028c4478109a67965a0e5b1e,
    default_namespace: "ds",
    contracts: array![
        (selector_from_tag!("ds-actions"), TryInto::<felt252, ClassHash>::try_into(0x042b2956c0cc58577bbdad2f24191dcf8282ece7d483d04b17e8c3eacc6141bd).unwrap(), array![]),
    ],
    models: array![
        TryInto::<felt252, ClassHash>::try_into(0x02beadba1d1f8e38aa90d6311d620805aab89a252950424c419705ceb0d1c4fb).unwrap(),
        TryInto::<felt252, ClassHash>::try_into(0x02dca898b48c80c247ce2e74e7230f3e568224f5074441a659259cf4dea550d4).unwrap(),
        TryInto::<felt252, ClassHash>::try_into(0x05fc0ef5e3616e4b5e9cca551fd96915e36856b63397c9fc81bcfe238e1ac40a).unwrap(),
        TryInto::<felt252, ClassHash>::try_into(0x06d3d9a8a689da03f37a9115a732f8fd52550f16c55b6f025ea6d5babc9696ea).unwrap(),
    ],
    events: array![
        TryInto::<felt252, ClassHash>::try_into(0x0230eecc57fafed34e962a655d958411f9e84bdf1c3abf223dde7bd93f346d9b).unwrap(),
    ],
};
```

on this [dojo PR](https://github.com/dojoengine/dojo/pull/3362) you can build sozo and run:
```bash
sozo inspect --output-factory
```

This will output something like this:
```bash
sozo -P <PROFILE> execute factory set_config <VERSION> 0x057994b6a75fad550ca18b41ee82e2110e158c59028c4478109a67965a0e5b1e str:ds 1 0x051ca47f464277070d0ef7e920eeb1ad3e1554f6264181b7f946fb0a7491564b 0x042b2956c0cc58577bbdad2f24191dcf8282ece7d483d04b17e8c3eacc6141bd 0 4 0x02beadba1d1f8e38aa90d6311d620805aab89a252950424c419705ceb0d1c4fb 0x02dca898b48c80c247ce2e74e7230f3e568224f5074441a659259cf4dea550d4 0x05fc0ef5e3616e4b5e9cca551fd96915e36856b63397c9fc81bcfe238e1ac40a 0x06d3d9a8a689da03f37a9115a732f8fd52550f16c55b6f025ea6d5babc9696ea 1 0x0230eecc57fafed34e962a655d958411f9e84bdf1c3abf223dde7bd93f346d9b
```

Where `VERSION` can be anything as a key of the model for `FactoryConfig`. And the other arguments is the serialized `FactoryConfig`.

And then call the `deploy` entrypoint to deploy a new world:
```bash
sozo -P <PROFILE> execute factory deploy str:world1 <VERSION> <SERIALIZED_WORLD_CONFIG>
```

Where the `WorldConfig` could change based on your needs.
