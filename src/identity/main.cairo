#[starknet::contract]
mod Identity {
    use starknet::ContractAddress;
    use starknet::contract_address::ContractAddressZeroable;
    use starknet::{get_caller_address, get_contract_address};
    use starknet::{SyscallResultTrait, StorageBaseAddress, storage_base_address_from_felt252};
    use traits::Into;
    use array::{ArrayTrait, SpanTrait};
    use zeroable::Zeroable;
    use starknet::class_hash::ClassHash;
    use identity::interface::identity::{IIdentity, IIdentityDispatcher, IIdentityDispatcherTrait};
    use integer::{u256_safe_divmod, u256_as_non_zero};
    use core::pedersen;
    use storage_read::{main::storage_read_component, interface::IStorageRead};
    use custom_uri::{interface::IInternalCustomURI, main::custom_uri_component};
    use openzeppelin::{
        account, access::ownable::OwnableComponent,
        upgrades::{UpgradeableComponent, interface::IUpgradeable},
        token::erc721::{
            ERC721Component, erc721::ERC721Component::InternalTrait as ERC721InternalTrait
        },
        introspection::{src5::SRC5Component, dual_src5::{DualCaseSRC5, DualCaseSRC5Trait}}
    };
    use identity::identity::{internal::InternalTrait};

    const USER_DATA_ADDR: felt252 =
        1043580099640415304067929596039389735845630832049981224284932480360577081706;
    const VERIFIER_DATA_ADDR: felt252 =
        304878986635684253299743444353489138340069571156984851619649640349195152192;

    component!(path: custom_uri_component, storage: custom_uri, event: CustomUriEvent);
    component!(path: storage_read_component, storage: storage_read, event: StorageReadEvent);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);
    component!(path: ERC721Component, storage: erc721, event: ERC721Event);
    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);
    component!(path: UpgradeableComponent, storage: upgradeable, event: UpgradeableEvent);


    // allow to check what interface is supported
    #[abi(embed_v0)]
    impl SRC5Impl = SRC5Component::SRC5Impl<ContractState>;
    #[abi(embed_v0)]
    impl SRC5CamelImpl = SRC5Component::SRC5CamelImpl<ContractState>;
    impl SRC5InternalImpl = SRC5Component::InternalImpl<ContractState>;
    // make it a NFT
    #[abi(embed_v0)]
    impl ERC721Impl = ERC721Component::ERC721Impl<ContractState>;
    #[abi(embed_v0)]
    impl ERC721CamelOnlyImpl = ERC721Component::ERC721CamelOnlyImpl<ContractState>;
    // allow to query name of nft collection
    #[abi(embed_v0)]
    impl IERC721MetadataImpl =
        identity::identity::erc721::IERC721MetadataImpl<ContractState>;
    // allow to query nft metadata json
    #[abi(embed_v0)]
    impl StorageReadImpl = storage_read_component::StorageRead<ContractState>;
    // add an owner
    #[abi(embed_v0)]
    impl OwnableImpl = OwnableComponent::OwnableImpl<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;
    // make it upgradable
    impl UpgradeableInternalImpl = UpgradeableComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        user_data: LegacyMap<(u128, felt252), felt252>,
        verifier_data: LegacyMap<(u128, felt252, ContractAddress), felt252>,
        main_id_by_addr: LegacyMap<ContractAddress, u128>,
        // legacy owner
        Proxy_admin: felt252,
        #[substorage(v0)]
        custom_uri: custom_uri_component::Storage,
        #[substorage(v0)]
        storage_read: storage_read_component::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        #[substorage(v0)]
        erc721: ERC721Component::Storage,
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
        #[substorage(v0)]
        upgradeable: UpgradeableComponent::Storage
    }

    // 
    // Events
    // 

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        VerifierDataUpdate: VerifierDataUpdate,
        ExtendedVerifierDataUpdate: ExtendedVerifierDataUpdate,
        UserDataUpdate: UserDataUpdate,
        ExtendedUserDataUpdate: ExtendedUserDataUpdate,
        MainIdUpdate: MainIdUpdate,
        // components
        #[flat]
        CustomUriEvent: custom_uri_component::Event,
        #[flat]
        StorageReadEvent: storage_read_component::Event,
        #[flat]
        SRC5Event: SRC5Component::Event,
        #[flat]
        ERC721Event: ERC721Component::Event,
        #[flat]
        OwnableEvent: OwnableComponent::Event,
        #[flat]
        UpgradeableEvent: UpgradeableComponent::Event
    }

    #[derive(Drop, starknet::Event)]
    struct VerifierDataUpdate {
        #[key]
        id: u128,
        field: felt252,
        _data: felt252,
        verifier: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    struct ExtendedVerifierDataUpdate {
        #[key]
        id: u128,
        field: felt252,
        _data: Span<felt252>,
        verifier: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    struct UserDataUpdate {
        #[key]
        id: u128,
        field: felt252,
        _data: felt252,
    }

    #[derive(Drop, starknet::Event)]
    struct ExtendedUserDataUpdate {
        #[key]
        id: u128,
        field: felt252,
        _data: Span<felt252>,
    }

    #[derive(Drop, starknet::Event)]
    struct MainIdUpdate {
        #[key]
        owner: ContractAddress,
        id: u128,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState, owner: ContractAddress, token_uri_base: Span<felt252>,
    ) {
        self.ownable.initializer(owner);
        self.erc721.initializer('Starknet.id', 'ID');
        self.custom_uri.set_base_uri(token_uri_base);
    }

    #[external(v0)]
    impl UpgradeableImpl of IUpgradeable<ContractState> {
        fn upgrade(ref self: ContractState, new_class_hash: ClassHash) {
            self.ownable.assert_only_owner();
            self.upgradeable._upgrade(new_class_hash);
        }
    }

    #[external(v0)]
    impl IdentityImpl of IIdentity<ContractState> {
        fn owner_from_id(self: @ContractState, id: u128) -> ContractAddress {
            self.erc721.ERC721_owners.read(u256 { low: id, high: 0 })
        }

        fn get_main_id(self: @ContractState, user: ContractAddress) -> u128 {
            let main_id = self.main_id_by_addr.read(user);
            if self.erc721._owner_of(main_id.into()) == user {
                main_id
            } else {
                // if you transfer your main_id to someone, it is no longer your main_id
                0
            }
        }

        fn get_user_data(self: @ContractState, id: u128, field: felt252, domain: u32) -> felt252 {
            // todo: when volition comes, check on the specified domain
            self.user_data.read((id, field))
        }

        fn get_crosschecked_user_data(self: @ContractState, id: u128, field: felt252) -> felt252 {
            // todo: when volition comes, check on domain 0, if empty, check on volition
            self.user_data.read((id, field))
        }

        fn get_extended_user_data(
            self: @ContractState, id: u128, field: felt252, length: felt252, domain: u32
        ) -> Span<felt252> {
            self
                .get_extended(
                    USER_DATA_ADDR, array![id.into(), field].span(), length.into(), domain,
                )
        }

        fn get_unbounded_user_data(
            self: @ContractState, id: u128, field: felt252, domain: u32
        ) -> Span<felt252> {
            self.get_unbounded(USER_DATA_ADDR, array![id.into(), field].span(), domain,)
        }


        fn get_verifier_data(
            self: @ContractState, id: u128, field: felt252, verifier: ContractAddress, domain: u32
        ) -> felt252 {
            // todo: when volition comes, check on the specified domain
            self.verifier_data.read((id, field, verifier))
        }

        fn get_extended_verifier_data(
            self: @ContractState,
            id: u128,
            field: felt252,
            length: felt252,
            verifier: ContractAddress,
            domain: u32
        ) -> Span<felt252> {
            self
                .get_extended(
                    VERIFIER_DATA_ADDR,
                    array![id.into(), field, verifier.into()].span(),
                    length.into(),
                    domain,
                )
        }

        fn get_unbounded_verifier_data(
            self: @ContractState, id: u128, field: felt252, verifier: ContractAddress, domain: u32
        ) -> Span<felt252> {
            self
                .get_unbounded(
                    VERIFIER_DATA_ADDR, array![id.into(), field, verifier.into()].span(), domain,
                )
        }

        fn get_crosschecked_verifier_data(
            self: @ContractState, id: u128, field: felt252, verifier: ContractAddress
        ) -> felt252 {
            // todo: when volition comes, check on domain 0, if empty, check on volition
            self.verifier_data.read((id, field, verifier))
        }

        fn mint(ref self: ContractState, id: u128) {
            self.erc721._mint(get_caller_address(), id.into());
        }

        fn set_main_id(ref self: ContractState, id: u128) {
            let caller = get_caller_address();
            assert(caller == self.erc721._owner_of(id.into()), 'you don\'t own this id');
            self.main_id_by_addr.write(caller, id);
            self.emit(Event::MainIdUpdate(MainIdUpdate { id, owner: caller }));
        }

        fn reset_main_id(ref self: ContractState) {
            let id = self.main_id_by_addr.read(get_caller_address());
            self.main_id_by_addr.write(get_caller_address(), 0);
            self
                .emit(
                    Event::MainIdUpdate(MainIdUpdate { id, owner: ContractAddressZeroable::zero() })
                );
        }

        fn set_user_data(
            ref self: ContractState, id: u128, field: felt252, data: felt252, domain: u32
        ) {
            let caller = get_caller_address();
            assert(caller == self.erc721._owner_of(id.into()), 'you don\'t own this id');
            self.user_data.write((id, field), data);
            self.emit(Event::UserDataUpdate(UserDataUpdate { id, field, _data: data }))
        }

        fn set_extended_user_data(
            ref self: ContractState, id: u128, field: felt252, data: Span<felt252>, domain: u32
        ) {
            let caller = get_caller_address();
            assert(caller == self.erc721._owner_of(id.into()), 'you don\'t own this id');
            self.set(USER_DATA_ADDR, array![id.into(), field].span(), data, domain);
            self
                .emit(
                    Event::ExtendedUserDataUpdate(
                        ExtendedUserDataUpdate { id, field, _data: data, }
                    )
                );
        }

        fn set_verifier_data(
            ref self: ContractState, id: u128, field: felt252, data: felt252, domain: u32
        ) {
            // todo: when volition comes, handle the domain
            let verifier = get_caller_address();
            self.verifier_data.write((id, field, verifier), data);
            self
                .emit(
                    Event::VerifierDataUpdate(
                        VerifierDataUpdate { id, field, _data: data, verifier, }
                    )
                )
        }

        fn set_extended_verifier_data(
            ref self: ContractState, id: u128, field: felt252, data: Span<felt252>, domain: u32
        ) {
            let verifier = get_caller_address();
            self
                .set(
                    VERIFIER_DATA_ADDR,
                    array![id.into(), field, verifier.into()].span(),
                    data,
                    domain
                );
            self
                .emit(
                    Event::ExtendedVerifierDataUpdate(
                        ExtendedVerifierDataUpdate { id, field, _data: data, verifier, }
                    )
                );
        }

        // this function should be called after upgrading from Cairo 0 contract
        fn finalize_migration(ref self: ContractState, token_uri_base: Span<felt252>) {
            let caller = get_caller_address();
            assert(caller.into() == self.Proxy_admin.read(), 'only proxy admin can migrate');
            self.ownable.initializer(caller);
            self.custom_uri.set_base_uri(token_uri_base);
        }
    }
}
