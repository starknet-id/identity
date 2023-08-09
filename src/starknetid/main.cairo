use core::array::SpanTrait;
#[starknet::contract]
mod StarknetId {
    use starknet::ContractAddress;
    use starknet::contract_address::ContractAddressZeroable;
    use starknet::{get_caller_address, get_contract_address};
    use traits::Into;
    use array::{ArrayTrait, SpanTrait};
    use zeroable::Zeroable;
    use starknet::class_hash::ClassHash;
    use identity::interface::starknetid::{
        IStarknetId, IStarknetIdDispatcher, IStarknetIdDispatcherTrait
    };
    use integer::{u256_safe_divmod, u256_as_non_zero};
    use core::pedersen;


    #[storage]
    struct Storage {}

    #[constructor]
    fn constructor(ref self: ContractState) {}

    #[external(v0)]
    impl NamingImpl of IStarknetId<ContractState> {
        fn get_user_data(
            self: @ContractState, starknet_id: felt252, field: felt252, domain: felt252
        ) -> felt252 {
            1
        }

        fn get_crosschecked_user_data(
            self: @ContractState, starknet_id: felt252, field: felt252
        ) -> felt252 {
            1
        }


        fn get_verifier_data(
            self: @ContractState, starknet_id: felt252, field: felt252, domain: felt252
        ) -> felt252 {
            1
        }


        fn get_crosschecked_verifier_data(
            self: @ContractState, starknet_id: felt252, field: felt252
        ) -> felt252 {
            1
        }
    }
}
