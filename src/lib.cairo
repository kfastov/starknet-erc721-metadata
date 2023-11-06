use array::ArrayTrait;
use starknet::ContractAddress;

// The amount of tokens that can be minted at once.
// Attempt to mint too many tokens can lead
// to large amount of gas being used and long gas estimation
const MAX_MINT_AMOUNT: u256 = 5000;

#[starknet::interface]
trait IERC721IPFSTemplate<TContractState> {
    // Standard ERC721 + ERC721Metadata methods
    fn name(self: @TContractState) -> felt252;
    fn symbol(self: @TContractState) -> felt252;
    fn token_uri(self: @TContractState, token_id: u256) -> Array<felt252>;
    fn supports_interface(self: @TContractState, interface_id: felt252) -> bool;
    fn balance_of(self: @TContractState, account: ContractAddress) -> u256;
    fn owner_of(self: @TContractState, token_id: u256) -> ContractAddress;
    fn get_approved(self: @TContractState, token_id: u256) -> ContractAddress;
    fn is_approved_for_all(
        self: @TContractState, owner: ContractAddress, operator: ContractAddress
    ) -> bool;
    fn approve(ref self: TContractState, to: ContractAddress, token_id: u256);
    fn set_approval_for_all(ref self: TContractState, operator: ContractAddress, approved: bool);
    fn transfer_from(
        ref self: TContractState, from: ContractAddress, to: ContractAddress, token_id: u256
    );
    fn safe_transfer_from(
        ref self: TContractState,
        from: ContractAddress,
        to: ContractAddress,
        token_id: u256,
        data: Span<felt252>
    );
    // camelCase methods that duplicate the main snake_case interface for compatibility
    fn tokenURI(self: @TContractState, tokenId: u256) -> Array<felt252>;
    fn supportsInterface(self: @TContractState, interfaceId: felt252) -> bool;
    fn balanceOf(self: @TContractState, account: ContractAddress) -> u256;
    fn ownerOf(self: @TContractState, tokenId: u256) -> ContractAddress;
    fn getApproved(self: @TContractState, tokenId: u256) -> ContractAddress;
    fn isApprovedForAll(
        self: @TContractState, owner: ContractAddress, operator: ContractAddress
    ) -> bool;
    fn setApprovalForAll(ref self: TContractState, operator: ContractAddress, approved: bool);
    fn transferFrom(
        ref self: TContractState, from: ContractAddress, to: ContractAddress, tokenId: u256
    );
    fn safeTransferFrom(
        ref self: TContractState,
        from: ContractAddress,
        to: ContractAddress,
        tokenId: u256,
        data: Span<felt252>
    );
    // Non-standard method for minting new NFTs. Can be called by admin only
    fn mint(ref self: TContractState, recipient: ContractAddress, amount: u256);
    fn mint_to_owner(ref self: TContractState, amount: u256);
    // methods for retrieving supply
    fn max_supply(self: @TContractState) -> u256;
    fn total_supply(self: @TContractState) -> u256;
    // and their camelCase equivalents
    fn maxSupply(self: @TContractState) -> u256;
    fn totalSupply(self: @TContractState) -> u256;
    // method for setting base URI common for all tokens
    // TODO move this into constructor
    fn set_base_uri(ref self: TContractState, base_uri: Array<felt252>);
    fn airdrop(ref self: TContractState, recipients: Array<ContractAddress>);
}

#[starknet::contract]
mod ERC721IPFSTemplate {
    use openzeppelin::token::erc721::erc721::ERC721::ERC721_owners::InternalContractMemberStateTrait as ERC721OwnersTrait;
    use openzeppelin::token::erc721::erc721::ERC721::ERC721_balances::InternalContractMemberStateTrait as ERC721BalancesTrait;
    use starknet::ContractAddress;
    use starknet::ClassHash;
    use openzeppelin::token::erc721::ERC721;
    use alexandria_ascii::integer::ToAsciiTrait;
    use openzeppelin::access::ownable::Ownable as ownable_component;
    use openzeppelin::upgrades::upgradeable::Upgradeable as upgradeable_component;
    use openzeppelin::upgrades::interface::IUpgradeable;

    component!(path: ownable_component, storage: ownable, event: OwnableEvent);
    component!(path: upgradeable_component, storage: upgradeable, event: UpgradeableEvent);

    /// Ownable
    #[abi(embed_v0)]
    impl OwnableImpl = ownable_component::OwnableImpl<ContractState>;
    #[abi(embed_v0)]
    impl OwnableCamelOnlyImpl =
        ownable_component::OwnableCamelOnlyImpl<ContractState>;
    impl InternalImpl = ownable_component::InternalImpl<ContractState>;

    /// Upgradeable
    impl UpgradeableInternalImpl = upgradeable_component::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        max_supply: u256,
        last_token_id: u256,
        base_uri_len: u32,
        base_uri: LegacyMap<u32, felt252>,
        is_sold: LegacyMap<u256, bool>,
        unsold_quantity: u256,
        default_owner: ContractAddress,
        #[substorage(v0)]
        ownable: ownable_component::Storage,
        #[substorage(v0)]
        upgradeable: upgradeable_component::Storage
    }

    mod Errors {
        const MINT_ZERO_AMOUNT: felt252 = 'mint amount should be >= 1';
        const MINT_AMOUNT_TOO_LARGE: felt252 = 'mint amount too large';
        const MINT_MAX_SUPPLY_EXCEEDED: felt252 = 'max supply exceeded';
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        Transfer: Transfer,
        Approval: Approval,
        ApprovalForAll: ApprovalForAll,
        OwnableEvent: ownable_component::Event,
        UpgradeableEvent: upgradeable_component::Event,
    }

    #[derive(Drop, starknet::Event)]
    struct Transfer {
        #[key]
        from: ContractAddress,
        #[key]
        to: ContractAddress,
        #[key]
        token_id: u256
    }

    #[derive(Drop, starknet::Event)]
    struct Approval {
        #[key]
        owner: ContractAddress,
        #[key]
        approved: ContractAddress,
        #[key]
        token_id: u256
    }

    #[derive(Drop, starknet::Event)]
    struct ApprovalForAll {
        #[key]
        owner: ContractAddress,
        #[key]
        operator: ContractAddress,
        approved: bool
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        admin: ContractAddress,
        name: felt252,
        symbol: felt252,
        max_supply: u256
    ) {
        self.max_supply.write(max_supply);
        self.default_owner.write(admin);

        let mut unsafe_state = ERC721::unsafe_new_contract_state();
        ERC721::InternalImpl::initializer(ref unsafe_state, name, symbol);

        self.ownable.initializer(admin);
    }

    #[external(v0)]
    impl UpgradeableImpl of IUpgradeable<ContractState> {
        fn upgrade(ref self: ContractState, new_class_hash: ClassHash) {
            // This function can only be called by the owner
            self.ownable.assert_only_owner();

            // Replace the class hash upgrading the contract
            self.upgradeable._upgrade(new_class_hash);
        }
    }

    #[generate_trait]
    impl ERC721IPFSTemplateInternalImpl of ERC721IPFSTemplateInternalTrait {
        fn _spawn_owner_token(
            ref self: ContractState, token_id: u256
        ) {
            let mut unsafe_state = ERC721::unsafe_new_contract_state();
            let owner = self.default_owner.read();
            unsafe_state.ERC721_owners.write(token_id, self.default_owner.read());
            self.unsold_quantity.write(self.unsold_quantity.read() - 1);
            unsafe_state.ERC721_balances.write(owner, unsafe_state.ERC721_balances.read(owner) + 1);
            self.is_sold.write(token_id, true);
        }
    }

    #[external(v0)]
    impl ERC721IPFSTemplateImpl of super::IERC721IPFSTemplate<ContractState> {
        fn name(self: @ContractState) -> felt252 {
            let unsafe_state = ERC721::unsafe_new_contract_state();
            ERC721::ERC721MetadataImpl::name(@unsafe_state)
        }

        fn symbol(self: @ContractState) -> felt252 {
            let unsafe_state = ERC721::unsafe_new_contract_state();
            ERC721::ERC721MetadataImpl::symbol(@unsafe_state)
        }

        fn token_uri(self: @ContractState, token_id: u256) -> Array<felt252> {
            let mut uri = ArrayTrait::new();

            // retrieve base_uri from the storage and append to the uri string
            let mut i = 0;
            loop {
                if i >= self.base_uri_len.read() {
                    break;
                }
                uri.append(self.base_uri.read(i));
                i += 1;
            };

            let token_id_ascii = token_id.to_ascii();

            let mut i = 0;
            loop {
                if i >= token_id_ascii.len() {
                    break;
                }
                uri.append(*token_id_ascii.at(i));
                i += 1;
            };

            uri.append('.json');
            uri
        }

        fn supports_interface(self: @ContractState, interface_id: felt252) -> bool {
            let unsafe_state = ERC721::unsafe_new_contract_state();
            ERC721::SRC5Impl::supports_interface(@unsafe_state, interface_id)
        }

        fn supportsInterface(self: @ContractState, interfaceId: felt252) -> bool {
            let unsafe_state = ERC721::unsafe_new_contract_state();
            ERC721::SRC5CamelImpl::supportsInterface(@unsafe_state, interfaceId)
        }

        fn tokenURI(self: @ContractState, tokenId: u256) -> Array<felt252> {
            ERC721IPFSTemplateImpl::token_uri(self, tokenId)
        }

        fn balance_of(self: @ContractState, account: ContractAddress) -> u256 {
            let unsafe_state = ERC721::unsafe_new_contract_state();
            ERC721::ERC721Impl::balance_of(@unsafe_state, account) +
                if account == self.default_owner.read() {
                    self.unsold_quantity.read()
                } else {
                    0
                }
        }

        fn owner_of(self: @ContractState, token_id: u256) -> ContractAddress {
            let unsafe_state = ERC721::unsafe_new_contract_state();

            if !self.is_sold.read(token_id) {
                return self.default_owner.read();
            }
            
            ERC721::ERC721Impl::owner_of(@unsafe_state, token_id)
        }

        fn get_approved(self: @ContractState, token_id: u256) -> ContractAddress {
            // if not sold, return empty address (approved to nobody)
            if !self.is_sold.read(token_id) {
                return Zeroable::zero();
            }

            let unsafe_state = ERC721::unsafe_new_contract_state();
            ERC721::ERC721Impl::get_approved(@unsafe_state, token_id)
        }

        fn is_approved_for_all(
            self: @ContractState, owner: ContractAddress, operator: ContractAddress
        ) -> bool {
            let unsafe_state = ERC721::unsafe_new_contract_state();
            ERC721::ERC721Impl::is_approved_for_all(@unsafe_state, owner, operator)
        }

        fn approve(ref self: ContractState, to: ContractAddress, token_id: u256) {
            let mut unsafe_state = ERC721::unsafe_new_contract_state();
            // if not sold, mint really to default owner at first, than basic transfer
            if !self.is_sold.read(token_id) {
                self._spawn_owner_token(token_id);
            }

            ERC721::ERC721Impl::approve(ref unsafe_state, to, token_id)
        }

        fn set_approval_for_all(
            ref self: ContractState, operator: ContractAddress, approved: bool
        ) {
            let mut unsafe_state = ERC721::unsafe_new_contract_state();
            ERC721::ERC721Impl::set_approval_for_all(ref unsafe_state, operator, approved)
        }

        fn transfer_from(
            ref self: ContractState, from: ContractAddress, to: ContractAddress, token_id: u256
        ) {
            let mut unsafe_state = ERC721::unsafe_new_contract_state();

            // if not sold, mint really to default owner at first, than basic transfer
            if !self.is_sold.read(token_id) {
                self._spawn_owner_token(token_id);
            }

            ERC721::ERC721Impl::transfer_from(ref unsafe_state, from, to, token_id)
        }

        fn safe_transfer_from(
            ref self: ContractState,
            from: ContractAddress,
            to: ContractAddress,
            token_id: u256,
            data: Span<felt252>
        ) {
            let mut unsafe_state = ERC721::unsafe_new_contract_state();

            // if not sold, mint really to default owner at first, than basic transfer
            if !self.is_sold.read(token_id) {
                self._spawn_owner_token(token_id);
            }

            ERC721::ERC721Impl::safe_transfer_from(ref unsafe_state, from, to, token_id, data)
        }

        fn balanceOf(self: @ContractState, account: ContractAddress) -> u256 {
            self.balance_of(account)
        }

        fn ownerOf(self: @ContractState, tokenId: u256) -> ContractAddress {
            self.owner_of(tokenId)
        }

        fn getApproved(self: @ContractState, tokenId: u256) -> ContractAddress {
            self.get_approved(tokenId)
        }

        fn isApprovedForAll(
            self: @ContractState, owner: ContractAddress, operator: ContractAddress
        ) -> bool {
            let unsafe_state = ERC721::unsafe_new_contract_state();
            ERC721::ERC721CamelOnlyImpl::isApprovedForAll(@unsafe_state, owner, operator)
        }

        fn setApprovalForAll(ref self: ContractState, operator: ContractAddress, approved: bool) {
            let mut unsafe_state = ERC721::unsafe_new_contract_state();
            ERC721::ERC721CamelOnlyImpl::setApprovalForAll(ref unsafe_state, operator, approved)
        }

        fn transferFrom(
            ref self: ContractState, from: ContractAddress, to: ContractAddress, tokenId: u256
        ) {
            self.transfer_from(from, to, tokenId)
        }

        fn safeTransferFrom(
            ref self: ContractState,
            from: ContractAddress,
            to: ContractAddress,
            tokenId: u256,
            data: Span<felt252>
        ) {
            let mut unsafe_state = ERC721::unsafe_new_contract_state();
            ERC721::ERC721CamelOnlyImpl::safeTransferFrom(ref unsafe_state, from, to, tokenId, data)
        }

        // Non-standard method for minting new NFTs. Can be called by admin only
        fn mint(ref self: ContractState, recipient: ContractAddress, amount: u256) {
            // check if sender is the owner of the contract
            self.ownable.assert_only_owner();
            assert(amount > 0, Errors::MINT_ZERO_AMOUNT);
            // check mint amount validity
            assert(amount <= super::MAX_MINT_AMOUNT, Errors::MINT_AMOUNT_TOO_LARGE);
            // get the last id
            let last_token_id = self.last_token_id.read();
            // calculate the last id after mint (maybe use safe math if available)
            let last_mint_id = last_token_id + amount;
            // don't mint more than the preconfigured max supply
            let max_supply = self.max_supply.read();
            assert(last_mint_id <= max_supply, Errors::MINT_MAX_SUPPLY_EXCEEDED);
            // call mint sequentially
            let mut unsafe_state = ERC721::unsafe_new_contract_state();
            let mut token_id = last_token_id + 1;
            loop {
                if token_id > last_mint_id {
                    break;
                }
                self.is_sold.write(token_id, true);
                ERC721::InternalImpl::_mint(ref unsafe_state, recipient, token_id);
                token_id += 1;
            };
            // Save the id of last minted token
            self.last_token_id.write(last_mint_id);
        }

        // Non-standard method for minting new NFTs. Can be called by admin only
        fn mint_to_owner(ref self: ContractState, amount: u256) {
            // check if sender is the owner of the contract
            self.ownable.assert_only_owner();
            assert(amount > 0, Errors::MINT_ZERO_AMOUNT);
            // check mint amount validity
            assert(amount <= super::MAX_MINT_AMOUNT, Errors::MINT_AMOUNT_TOO_LARGE);
            // get the last id
            let last_token_id = self.last_token_id.read();
            // calculate the last id after mint (maybe use safe math if available)
            let last_mint_id = last_token_id + amount;
            // don't mint more than the preconfigured max supply
            let max_supply = self.max_supply.read();
            assert(last_mint_id <= max_supply, Errors::MINT_MAX_SUPPLY_EXCEEDED);
            // call mint sequentially
            let owner = self.default_owner.read();
            let mut unsafe_state = ERC721::unsafe_new_contract_state();
            let mut token_id = last_token_id + 1;
            loop {
                if token_id > last_mint_id {
                    break;
                }
                // don't mint really, just emit mint events
                self.emit(Transfer { from: Zeroable::zero(), to: owner, token_id });
                token_id += 1;
            };
            // Save the id of last minted token
            self.last_token_id.write(last_mint_id);
            self.unsold_quantity.write(self.unsold_quantity.read() + amount);
        }

        fn max_supply(self: @ContractState) -> u256 {
            self.max_supply.read()
        }

        fn total_supply(self: @ContractState) -> u256 {
            self.last_token_id.read()
        }

        fn maxSupply(self: @ContractState) -> u256 {
            ERC721IPFSTemplateImpl::max_supply(self)
        }

        fn totalSupply(self: @ContractState) -> u256 {
            ERC721IPFSTemplateImpl::total_supply(self)
        }

        fn set_base_uri(ref self: ContractState, base_uri: Array<felt252>) {
            // check if sender is the owner of the contract
            self.ownable.assert_only_owner();

            let base_uri_len = base_uri.len();
            let mut i = 0;
            self.base_uri_len.write(base_uri_len);
            loop {
                if i >= base_uri.len() {
                    break;
                }
                self.base_uri.write(i, *base_uri.at(i));
                i += 1;
            }
        }
        fn airdrop(ref self: ContractState, recipients: Array<ContractAddress>) {
            self.ownable.assert_only_owner();
            // get the count of recipients
            let len = recipients.len();
            // get the last id
            let last_token_id = self.last_token_id.read();
            // calculate the last id after mint
            let last_mint_id = last_token_id + len.into();
            // don't mint more than the preconfigured max supply
            let max_supply = self.max_supply.read();
            assert(last_mint_id <= max_supply, Errors::MINT_MAX_SUPPLY_EXCEEDED);

            // get the ERC721 state for calling mint method
            let mut unsafe_state = ERC721::unsafe_new_contract_state();

            // iterate through all receivers and call mint
            let mut index = 0;
            loop {
                if index >= len {
                    break;
                }

                let recipient = *recipients.at(index);
                let token_id = last_token_id + 1 + index.into();
                ERC721::InternalImpl::_mint(ref unsafe_state, recipient, token_id);
                self.is_sold.write(token_id, true);
                index += 1;
            };
            // 
            // Save the id of last minted token
            self.last_token_id.write(last_mint_id);
        }
    }
}

#[cfg(test)]
mod tests {
    // Import the interface and dispatcher to be able to interact with the contract.
    use core::clone::Clone;
use super::{
        ERC721IPFSTemplate, IERC721IPFSTemplateDispatcher, IERC721IPFSTemplateDispatcherTrait
    };
    use openzeppelin::access::ownable::interface::{IOwnableDispatcher, IOwnableDispatcherTrait};
    use openzeppelin::upgrades::interface::{IUpgradeableDispatcher, IUpgradeableDispatcherTrait};

    // Import the deploy syscall to be able to deploy the contract.
    use starknet::class_hash::Felt252TryIntoClassHash;
    use starknet::{
        deploy_syscall, ContractAddress, get_contract_address, contract_address_const,
        class_hash_const
    };

    // Use starknet test utils to fake the transaction context.
    use starknet::testing::{set_caller_address, set_contract_address};

    // Deploy the contract and return its dispatcher.
    fn deploy(
        owner: ContractAddress, name: felt252, symbol: felt252, max_supply: u256
    ) -> (IERC721IPFSTemplateDispatcher, IOwnableDispatcher, IUpgradeableDispatcher) {
        // Set up constructor arguments.
        let mut calldata = ArrayTrait::new();
        owner.serialize(ref calldata);
        name.serialize(ref calldata);
        symbol.serialize(ref calldata);
        max_supply.serialize(ref calldata);

        // Declare and deploy
        let (contract_address, _) = deploy_syscall(
            ERC721IPFSTemplate::TEST_CLASS_HASH.try_into().unwrap(), 0, calldata.span(), false
        )
            .unwrap();

        // Return dispatchers.
        // The dispatcher allows to interact with the contract based on its interface.
        (
            IERC721IPFSTemplateDispatcher { contract_address },
            IOwnableDispatcher { contract_address },
            IUpgradeableDispatcher { contract_address }
        )
    }

    #[test]
    #[available_gas(2000000000)]
    fn test_deploy() {
        let owner = contract_address_const::<1>();
        let name = 'Cool Token';
        let symbol = 'COOL';
        let max_supply = 100000;
        let (contract, ownable, _) = deploy(owner, name, symbol, max_supply);

        assert(contract.name() == name, 'wrong name');
        assert(contract.symbol() == symbol, 'wrong symbol');
        assert(contract.max_supply() == max_supply, 'wrong max supply');

        assert(ownable.owner() == owner, 'wrong admin');
    }

    #[test]
    #[available_gas(2000000000)]
    fn test_mint() {
        let owner = contract_address_const::<123>();
        set_contract_address(owner);
        let (contract, _, _) = deploy(owner, 'Token', 'T', 300);

        // set the base URI
        let base_uri = array![
            'ipfs://lllllllllllllooooooooooo',
            'nnnnnnnnnnngggggggggggggggggggg',
            'aaaaddddddrrrrrreeeeeeesssss'
        ];
        contract.set_base_uri(base_uri.clone());

        let recipient = contract_address_const::<1>();
        contract.mint(recipient, 100);
        contract.mint(recipient, 50);

        assert(contract.total_supply() == 150, 'wrong total supply');
        assert(contract.balance_of(recipient) == 150, 'wrong balance after mint');
        assert(contract.owner_of(150) == recipient, 'wrong owner');
        let token_uri_array = contract.token_uri(150);
        assert(*token_uri_array.at(0) == *base_uri.at(0), 'wrong token uri (part 1)');
        assert(*token_uri_array.at(1) == *base_uri.at(1), 'wrong token uri (part 2)');
        assert(*token_uri_array.at(2) == *base_uri.at(2), 'wrong token uri (part 3)');
        assert(*token_uri_array.at(3) == '150', 'wrong token uri (token id)');
        assert(*token_uri_array.at(4) == '.json', 'wrong token uri (suffix)');
    }

    #[test]
    #[available_gas(2000000000)]
    fn test_mint_all_amount() {
        let owner = contract_address_const::<123>();
        set_contract_address(owner);

        let (contract, _, _) = deploy(owner, 'Token', 'T', 300);

        let recipient = contract_address_const::<1>();
        contract.mint(recipient, 300);
    }

    #[test]
    #[available_gas(2000000000)]
    fn test_can_transfer() {
        let owner = contract_address_const::<123>();
        let operator = contract_address_const::<456>();
        let recipient = contract_address_const::<789>();

        set_contract_address(owner);
        let (contract, _, _) = deploy(owner, 'Token', 'T', 300);

        // 1 - mint some tokens to owner
        contract.mint_to_owner(300);
        assert(contract.owner_of(123) == owner, 'wrong owner');

        // 2 - approve to operator
        contract.approve(operator, 123);
        assert(contract.get_approved(123) == operator, 'wrong operator');

        // 3 - transfer by operator to recipient
        set_contract_address(operator);
        contract.transfer_from(owner, recipient, 123);
        assert(contract.owner_of(123) == recipient, 'wrong owner');
    }

    #[test]
    #[available_gas(2000000000)]
    fn test_airdrop() {
        let recipients = array![
            contract_address_const::<1>(),
            contract_address_const::<2>(),
            contract_address_const::<3>(),
        ];

        let owner = contract_address_const::<4>();

        set_contract_address(owner);

        let (contract, _, _) = deploy(owner, 'Token', 'T', 300);

        // 1 - mint some tokens to owner
        contract.airdrop(recipients.clone());

        // 2 - check balances
        assert(contract.balance_of(*recipients.at(0)) == 1, 'wrong balance 1');
        assert(contract.balance_of(*recipients.at(1)) == 1, 'wrong balance 1');
        assert(contract.balance_of(*recipients.at(2)) == 1, 'wrong balance 1');

        // 3 - check ownership
        assert(contract.owner_of(1) == *recipients.at(0), 'wrong owner 1');
        assert(contract.owner_of(2) == *recipients.at(1), 'wrong owner 2');
        assert(contract.owner_of(3) == *recipients.at(2), 'wrong owner 3');
    }

    #[test]
    #[should_panic]
    #[available_gas(2000000000)]
    fn test_mint_not_admin() {
        let admin = contract_address_const::<1>();
        set_contract_address(admin);

        let (contract, _, _) = deploy(admin, 'Token', 'T', 300);

        let not_admin = contract_address_const::<2>();
        set_contract_address(not_admin);

        contract.mint(not_admin, 100);
    }

    #[test]
    #[should_panic]
    #[available_gas(2000000000)]
    fn test_mint_too_much() {
        let (contract, _, _) = deploy(contract_address_const::<123>(), 'Token', 'T', 300);
        contract.mint(get_contract_address(), 301);
    }

    #[test]
    #[ignore]
    #[available_gas(2000000000)]
    fn test_can_upgrade() {
        let owner = contract_address_const::<123>();
        set_contract_address(owner);

        let (contract, _, upgradeable) = deploy(owner, 'Token', 'T', 300);

        // TODO make it work actually
        let new_class_hash = class_hash_const::<234>();
        upgradeable.upgrade(new_class_hash);
    }
}
