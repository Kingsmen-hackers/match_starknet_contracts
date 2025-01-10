pub mod erc20;
use starknet::ContractAddress;


#[derive(Drop, Serde, Copy, starknet::Store)]
enum RequestLifecycle {
    #[default]
    PENDING,
    ACCEPTED_BY_SELLER,
    ACCEPTED_BY_BUYER,
    REQUEST_LOCKED,
    PAID,
    COMPLETED,
}

#[derive(Drop, Serde, Copy, starknet::Store)]
pub enum AccountType {
    #[default]
    BUYER,
    SELLER,
}

#[derive(Drop, Serde, Copy, starknet::Store)]
enum CoinPayment {
    #[default]
    USDC,
    STRK,
}

#[derive(Drop, Serde, starknet::Store)]
struct Request {
    id: u256,
    name: ByteArray,
    buyer_id: u256,
    sellers_price_quote: u256,
    locked_seller_id: u256,
    description: ByteArray,
    created_at: u256,
    lifecycle: RequestLifecycle,
    location: Location,
    updated_at: u256,
    paid: bool,
    accepted_offer_id: u256,
}

#[derive(Drop, Serde, Clone, starknet::Store)]
struct User {
    id: u256,
    username: ByteArray,
    phone: ByteArray,
    location: Location,
    created_at: u256,
    updated_at: u256,
    account_type: AccountType,
    location_enabled: bool,
    authority: ContractAddress,
}

#[derive(Drop, Serde, Copy, starknet::Store)]
struct Location {
    latitude: felt252,
    longitude: felt252,
}

#[derive(Drop, Serde, starknet::Store)]
struct Store {
    id: u256,
    name: ByteArray,
    description: ByteArray,
    phone: ByteArray,
    location: Location,
}

#[derive(Drop, Serde, Copy, starknet::Store)]
struct PaymentInfo {
    authority: ContractAddress,
    request_id: u256,
    buyer: ContractAddress,
    seller: ContractAddress,
    amount: u256,
    token: CoinPayment,
    created_at: u256,
    updated_at: u256,
}

#[starknet::interface]
pub trait IMatchStarknetContract<TContractState> { /// Create User
    fn create_user(
        ref self: TContractState,
        _username: ByteArray,
        _phone: ByteArray,
        _latitude: felt252,
        _longitude: felt252,
        _account_type: AccountType,
    );
    /// Update User
    fn update_user(
        ref self: TContractState,
        _username: ByteArray,
        _phone: ByteArray,
        _latitude: felt252,
        _longitude: felt252,
        _account_type: AccountType,
    );
    /// Create Store
    fn create_store(
        ref self: TContractState,
        _name: ByteArray,
        _description: ByteArray,
        _phone: ByteArray,
        _latitude: felt252,
        _longitude: felt252,
    );
    /// Create Request
    fn create_request(
        ref self: TContractState,
        _name: ByteArray,
        _description: ByteArray,
        _images: Span<ByteArray>,
        _latitude: felt252,
        _longitude: felt252,
    );
    /// Delete Request
    fn delete_request(ref self: TContractState, _request_id: u256);
    /// Mark Request As Completed
    fn mark_request_as_completed(ref self: TContractState, _request_id: u256);
    /// Withdraw Seller Profit
    fn withdraw_seller_profit(ref self: TContractState, coin: CoinPayment);
    /// Get Conversion Rate
    fn get_conversion_rate(self: @TContractState, request_id: u256, coin: CoinPayment) -> u256;
    /// pay for request token any other token apart strknet native token (STRK) -> usdc to strk
    /// equivalent
    fn pay_for_request_token(ref self: TContractState, request_id: u256, coin: CoinPayment);
    /// pay for request in strk (STRK)
    fn pay_for_request(ref self: TContractState, request_id: u256, coin: CoinPayment);
    /// toggle location
    fn toggle_location(ref self: TContractState);
    /// Get location preference
    fn get_location_preference(self: @TContractState, caller: ContractAddress) -> bool;
    /// Create offer
    fn create_offer(
        ref self: TContractState,
        _price: u256,
        _request_id: u256,
        _store_name: ByteArray,
        _images: Span<ByteArray>,
    );
    /// Accept offer
    fn accept_offer(ref self: TContractState, _offer_id: u256);
}
/// Contract for managing user points and redeeming them as tokens.
#[starknet::contract]
mod MatchStarknetContract {
    use core::num::traits::Pow;
    use starknet::storage::StoragePathEntry;
    use starknet::storage::{
        StoragePointerReadAccess, StoragePointerWriteAccess, Map, Vec, MutableVecTrait,
    };
    use starknet::{
        ContractAddress, get_block_timestamp, get_caller_address, get_contract_address, ClassHash,
        get_tx_info,
    };
    use core::array::ArrayTrait;
    use starknet::syscalls::deploy_syscall;
    use super::IMatchStarknetContract;
    use super::{
        AccountType, Location, RequestLifecycle, User, Request, Store, PaymentInfo, CoinPayment,
    };
    use pragma_lib::abi::{IPragmaABIDispatcher, IPragmaABIDispatcherTrait};
    use pragma_lib::types::{PragmaPricesResponse};
    use starknet::contract_address::contract_address_const;
    use crate::{erc20::IERC20Dispatcher, erc20::IERC20DispatcherTrait};
    use pragma_lib::types::{AggregationMode, DataType};


    #[derive(Drop, Serde, starknet::Store)]
    struct Offer {
        id: u256,
        price: u256,
        request_id: u256,
        store_name: ByteArray,
        seller_id: u256,
        is_accepted: bool,
        created_at: u256,
        updated_at: u256,
        authority: ContractAddress,
    }

    #[storage]
    struct Storage {
        price_oracles: Map<
            ContractAddress, felt252,
        >, // Mapping from token address to oracle address.
        user_points: Map<ContractAddress, PointData>, // Mapping from user address to PointData.
        donations: Map<ContractAddress, u256>, // Mapping from token address to amount donated.
        offer_images: Map<u256, Vec<ByteArray>>, // Mapping from offer id to image.
        request_images: Map<u256, Vec<ByteArray>>, // Mapping from request id to image.
        request_seller_ids: Map<u256, Vec<u256>>, // Mapping from request id to seller ids.
        request_offer_ids: Map<u256, Vec<u256>>,
        users: Map<ContractAddress, User>,
        users_by_id: Map<u256, User>,
        stores: Map<u256, Store>,
        requests: Map<u256, Request>,
        user_store_ids: Map<ContractAddress, Vec<u256>>,
        offers: Map<u256, Offer>,
        request_payment_info: Map<u256, PaymentInfo>,
        balance_of_usdc: Map<ContractAddress, u256>,
        balance_of_strk: Map<ContractAddress, u256>,
        user_counter: u256,
        store_counter: u256,
        request_counter: u256,
        offer_counter: u256,
        admin: ContractAddress, // Admin address.
        token_address: ContractAddress // Address of the ERC20 token contract.,
    }

    /// Struct representing user point data.
    #[derive(Drop, Serde, Copy, starknet::Store)]
    struct PointData {
        points: u256,
        updated_timestamp: u256,
        created_timestamp: u256,
    }


    /// Errors
    pub mod Errors {
        pub const MatchStarknetContract_ONLY_SELLERS_ALLOWED: felt252 = 'Only sellers';
        pub const MatchStarknetContract_UNAUTHORIZED_BUYER: felt252 = 'Unauthorized buyer';
        pub const MatchStarknetContract_ONLY_BUYERS_ALLOWED: felt252 = 'Only buyers allowed';
        pub const MatchStarknetContract_UNSUPPORTED_CHAIN_ID: felt252 = 'Unsupported chain id';
        pub const MatchStarknetContract_OFFER_ALREADY_ACCEPTED: felt252 = 'Offer already accepted';
        pub const MatchStarknetContract_INVALID_ACCOUNT_TYPE: felt252 = 'Invalid account type';
        pub const MatchStarknetContract_OFFER_ALREADY_EXISTS: felt252 = 'Offer already exists';
        pub const MatchStarknetContract_UNAUTHORIZED_REMOVAL: felt252 = 'Unauthorized removal';
        pub const MatchStarknetContract_REQUEST_NOT_ACCEPTED: felt252 = 'Request not accepted';
        pub const MatchStarknetContract_REQUEST_ALREADY_PAID: felt252 = 'Request already paid';
        pub const MatchStarknetContract_INSUFFICIENT_ALLOWANCE: felt252 = 'Insufficient allowance';
        pub const MatchStarknetContract_REQUEST_NOT_LOCKED: felt252 = 'Request not locked';
        pub const MatchStarknetContract_REQUEST_NOT_PAID: felt252 = 'Request not paid';
        pub const MatchStarknetContract_INSUFFICIENT_FUNDS: felt252 = 'Insufficient funds';
        pub const MatchStarknetContract_OFFER_NOT_REMOVABLE: felt252 = 'Offer not removable';
        pub const MatchStarknetContract_INDEX_OUT_OF_BOUNDS: felt252 = 'Index out of bounds';
        pub const MatchStarknetContract_REQUEST_LOCKED: felt252 = 'Request locked';
        pub const MatchStarknetContract_INVALID_USER: felt252 = 'Invalid user';
        pub const MatchStarknetContract_USER_ALREADY_EXISTS: felt252 = 'User already exists';
        pub const MatchStarknetContract_TOKEN_ASSOCIATION_FAILED: felt252 = 'Token assoc failed';
        pub const MatchStarknetContract_PRICE_CANNOT_BE_ZERO: felt252 = 'Price cannot be zero';
        pub const MatchStarknetContract_UNKNOWN_PAYMENT_TYPE: felt252 = 'Unknown payment type';
        pub const MatchStarknetContract_STORE_NEEDED_TO_CREATE_OFFER: felt252 =
            'Store needed to create offer';
    }

    /// Events
    #[event]
    #[derive(Drop, starknet::Event)]
    // The event enum must be annotated with the `#[event]` attribute.
    // It must also derive at least the `Drop` and `starknet::Event` traits.
    pub enum Event {
        AddPointFromWeight: AddPointFromWeight,
        RedeemCode: RedeemCode,
        Donated: Donated,
        WithdrawnDonation: WithdrawnDonation,
        ChangedAdmin: ChangedAdmin,
        UserCreated: UserCreated,
        UserUpdated: UserUpdated,
        StoreCreated: StoreCreated,
        OfferAccepted: OfferAccepted,
        RequestCreated: RequestCreated,
        RequestDeleted: RequestDeleted,
        RequestMarkedAsCompleted: RequestMarkedAsCompleted,
        OfferCreated: OfferCreated,
        RequestAccepted: RequestAccepted,
        RequestPaymentTransacted: RequestPaymentTransacted,
        OfferRemoved: OfferRemoved,
    }

    #[derive(Drop, starknet::Event)]
    pub struct UserCreated {
        pub user_address: ContractAddress,
        pub user_id: u256,
        pub username: ByteArray,
        pub account_type: AccountType,
    }

    #[derive(Drop, starknet::Event)]
    pub struct UserUpdated {
        pub user_address: ContractAddress,
        pub user_id: u256,
        pub username: ByteArray,
        pub account_type: AccountType,
    }

    #[derive(Drop, starknet::Event)]
    pub struct StoreCreated {
        pub seller_address: ContractAddress,
        pub store_id: u256,
        pub store_name: ByteArray,
        pub latitude: felt252,
        pub longitude: felt252,
    }

    #[derive(Drop, starknet::Event)]
    pub struct OfferAccepted {
        pub offer_id: u256,
        pub buyer_address: ContractAddress,
        pub is_accepted: bool,
    }

    #[derive(Drop, starknet::Event)]
    pub struct RequestCreated {
        pub request_id: u256,
        pub buyer_address: ContractAddress,
        pub request_name: ByteArray,
        pub latitude: felt252,
        pub longitude: felt252,
        pub images: Array<ByteArray>,
        pub lifecycle: RequestLifecycle,
        pub description: ByteArray,
        pub buyer_id: u256,
        pub seller_ids: Array<u256>,
        pub sellers_price_quote: felt252,
        pub locked_seller_id: u256,
        pub created_at: u256,
        pub updated_at: u256,
    }

    #[derive(Drop, starknet::Event)]
    pub struct RequestDeleted {
        pub request_id: u256,
    }

    #[derive(Drop, starknet::Event)]
    pub struct RequestMarkedAsCompleted {
        pub request_id: u256,
    }

    #[derive(Drop, starknet::Event)]
    pub struct OfferCreated {
        pub offer_id: u256,
        pub seller_address: ContractAddress,
        pub store_name: ByteArray,
        pub price: u256,
        pub request_id: u256,
        pub images: Array<ByteArray>,
        pub seller_id: u256,
        pub seller_ids: Array<ByteArray>,
    }

    #[derive(Drop, starknet::Event)]
    pub struct RequestAccepted {
        pub request_id: u256,
        pub offer_id: u256,
        pub seller_id: u256,
        pub updated_at: u256,
        pub sellers_price_quote: u256,
    }

    #[derive(Drop, starknet::Event)]
    pub struct RequestPaymentTransacted {
        pub timestamp: u256,
        pub amount: u256,
        pub token: CoinPayment,
        pub request_id: u256,
        pub seller_id: u256,
        pub buyer_id: u256,
        pub created_at: u256,
        pub updated_at: u256,
    }

    #[derive(Drop, starknet::Event)]
    pub struct OfferRemoved {
        pub offer_id: u256,
        pub seller_address: ContractAddress,
    }


    #[derive(Drop, starknet::Event)]
    pub struct AddPointFromWeight {
        pub points_to_add: u256,
        pub user: ContractAddress,
    }
    #[derive(Drop, starknet::Event)]
    pub struct RedeemCode {
        pub points_to_redeem: u256,
        pub user: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    pub struct Donated {
        pub token: ContractAddress,
        pub amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    pub struct WithdrawnDonation {
        pub token: ContractAddress,
        pub amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    pub struct ChangedAdmin {
        pub new_admin: ContractAddress,
    }


    const POINT_BASIS: u256 = 35;
    const TIME_TO_LOCK: u256 = 60;

    #[constructor]
    fn constructor(ref self: ContractState, class_hash: ClassHash) {
        let salt = 0;
        let unique = false;
        let mut calldata = array![];
        let (contract_address, _) = deploy_syscall(class_hash, salt, calldata.span(), unique)
            .unwrap();
        self.token_address.write(contract_address);
        self.price_oracles.entry(self.get_usdc_address()).write('STRK/USD');
        self.admin.write(get_caller_address());
    }

    #[abi(embed_v0)]
    impl MatchStarknetContractImpl of IMatchStarknetContract<ContractState> {
        fn create_user(
            ref self: ContractState,
            _username: ByteArray,
            _phone: ByteArray,
            _latitude: felt252,
            _longitude: felt252,
            _account_type: AccountType,
        ) {
            let user = self.users.entry(get_caller_address());
            assert(user.read().id == 0, Errors::MatchStarknetContract_USER_ALREADY_EXISTS);

            match _account_type {
                AccountType::BUYER => {},
                AccountType::SELLER => {},
                _ => { assert(false, Errors::MatchStarknetContract_INVALID_ACCOUNT_TYPE); },
            }

            let user_location = Location { latitude: _latitude, longitude: _longitude };
            let user_count = self.user_counter.read();
            let user_id = user_count + 1;
            self.user_counter.write(user_id);
            let new_user = User {
                id: user_id,
                username: _username.clone(),
                phone: _phone,
                location: user_location,
                created_at: get_block_timestamp().into(),
                updated_at: get_block_timestamp().into(),
                account_type: _account_type,
                location_enabled: true,
                authority: get_caller_address(),
            };

            user.write(new_user.clone());
            self.users_by_id.entry(user_id).write(new_user);

            self
                .emit(
                    UserCreated {
                        user_address: get_caller_address(),
                        user_id: user_id,
                        username: _username,
                        account_type: _account_type,
                    },
                );
        }
        fn update_user(
            ref self: ContractState,
            _username: ByteArray,
            _phone: ByteArray,
            _latitude: felt252,
            _longitude: felt252,
            _account_type: AccountType,
        ) {
            let user = self.users.entry(get_caller_address());
            assert(user.read().id != 0, Errors::MatchStarknetContract_INVALID_USER);
            user.username.write(_username.clone());
            user.phone.write(_phone.clone());
            user.location.write(Location { latitude: _latitude, longitude: _longitude });
            user.updated_at.write(get_block_timestamp().into());
            user.account_type.write(_account_type);
            let updated_user = self.users.entry(get_caller_address());

            self
                .emit(
                    UserUpdated {
                        user_address: get_caller_address(),
                        user_id: updated_user.read().id,
                        username: updated_user.read().username.clone(),
                        account_type: updated_user.read().account_type,
                    },
                );
        }
        fn create_store(
            ref self: ContractState,
            _name: ByteArray,
            _description: ByteArray,
            _phone: ByteArray,
            _latitude: felt252,
            _longitude: felt252,
        ) {
            let user = self.users.entry(get_caller_address());

            match user.read().account_type {
                AccountType::BUYER => {
                    assert(false, Errors::MatchStarknetContract_ONLY_SELLERS_ALLOWED);
                },
                AccountType::SELLER => {},
                _ => { assert(false, Errors::MatchStarknetContract_INVALID_ACCOUNT_TYPE); },
            }

            let store_location = Location { latitude: _latitude, longitude: _longitude };
            let store_count = self.store_counter.read();
            let store_id = store_count + 1;
            self.store_counter.write(store_id);
            let new_store = Store {
                id: store_id,
                name: _name.clone(),
                description: _description.clone(),
                phone: _phone.clone(),
                location: store_location,
            };
            self.stores.entry(store_id).write(new_store);
            self.user_store_ids.entry(get_caller_address()).append().write(store_id);

            self
                .emit(
                    StoreCreated {
                        seller_address: get_caller_address(),
                        store_id: store_id,
                        store_name: _name,
                        latitude: _latitude,
                        longitude: _longitude,
                    },
                );
        }
        fn create_request(
            ref self: ContractState,
            _name: ByteArray,
            _description: ByteArray,
            _images: Span<ByteArray>,
            _latitude: felt252,
            _longitude: felt252,
        ) {
            let user = self.users.entry(get_caller_address());

            match user.read().account_type {
                AccountType::BUYER => {},
                AccountType::SELLER => {
                    assert(false, Errors::MatchStarknetContract_ONLY_BUYERS_ALLOWED);
                },
                _ => { assert(false, Errors::MatchStarknetContract_INVALID_ACCOUNT_TYPE); },
            }
            let request_location = Location { latitude: _latitude, longitude: _longitude };
            let request_count = self.request_counter.read();
            let request_id = request_count + 1;
            self.request_counter.write(request_id);
            let new_request = Request {
                id: request_id,
                name: _name.clone(),
                buyer_id: user.read().id,
                sellers_price_quote: 0,
                locked_seller_id: 0,
                description: _description.clone(),
                created_at: get_block_timestamp().into(),
                lifecycle: RequestLifecycle::PENDING,
                location: request_location,
                updated_at: get_block_timestamp().into(),
                paid: false,
                accepted_offer_id: 0,
            };
            self.requests.entry(request_id).write(new_request);
            let mut request_images = self.request_images.entry(request_id);
            let mut images = _images;
            while let Option::Some(image) = images.pop_front() {
                request_images.append().write(image.clone());
            };

            let sellers_id: Array<u256> = ArrayTrait::new();

            self
                .emit(
                    RequestCreated {
                        request_id: request_id,
                        buyer_address: get_caller_address(),
                        request_name: _name,
                        latitude: _latitude,
                        longitude: _longitude,
                        images: _images.into(),
                        lifecycle: RequestLifecycle::PENDING,
                        description: _description,
                        buyer_id: user.read().id,
                        seller_ids: sellers_id,
                        sellers_price_quote: 0,
                        locked_seller_id: 0,
                        created_at: get_block_timestamp().into(),
                        updated_at: get_block_timestamp().into(),
                    },
                );
        }
        fn delete_request(ref self: ContractState, _request_id: u256) {
            let user = self.users.entry(get_caller_address());
            let request = self.requests.entry(_request_id);
            assert(
                user.read().id == request.read().buyer_id,
                Errors::MatchStarknetContract_UNAUTHORIZED_REMOVAL,
            );
            match request.read().lifecycle {
                RequestLifecycle::PENDING => {},
                _ => { assert(false, Errors::MatchStarknetContract_REQUEST_LOCKED); },
            }

            request.destruct();

            self.emit(RequestDeleted { request_id: _request_id });
        }

        fn mark_request_as_completed(ref self: ContractState, _request_id: u256) {
            let request = self.requests.entry(_request_id);
            let user = self.users.entry(get_caller_address());
            assert(
                request.read().buyer_id == user.read().id,
                Errors::MatchStarknetContract_UNAUTHORIZED_REMOVAL,
            );
            match request.read().lifecycle {
                RequestLifecycle::PAID => {},
                _ => { assert(false, Errors::MatchStarknetContract_REQUEST_NOT_PAID); },
            }

            assert(
                request.read().updated_at + TIME_TO_LOCK > get_block_timestamp().into(),
                Errors::MatchStarknetContract_REQUEST_NOT_LOCKED,
            );

            request.lifecycle.write(RequestLifecycle::COMPLETED);
            request.updated_at.write(get_block_timestamp().into());

            let payment_info = self.request_payment_info.entry(_request_id);
            let balance_of_usdc = self.balance_of_usdc.entry(payment_info.read().seller);
            let balance_of_strk = self.balance_of_strk.entry(payment_info.read().seller);

            if payment_info.read().amount > 0 {
                match payment_info.read().token {
                    CoinPayment::STRK => {
                        balance_of_strk.write(balance_of_strk.read() + payment_info.read().amount);
                    },
                    CoinPayment::USDC => {
                        balance_of_usdc.write(balance_of_usdc.read() + payment_info.read().amount);
                    },
                    _ => { assert(false, Errors::MatchStarknetContract_UNKNOWN_PAYMENT_TYPE); },
                }
            }

            self.emit(RequestMarkedAsCompleted { request_id: _request_id });
        }

        fn withdraw_seller_profit(ref self: ContractState, coin: CoinPayment) {
            let balance_of_usdc = self.balance_of_usdc.entry(get_caller_address());
            let balance_of_strk = self.balance_of_strk.entry(get_caller_address());
            match coin {
                CoinPayment::USDC => {
                    let amount = balance_of_usdc.read();
                    assert(amount > 0, Errors::MatchStarknetContract_INSUFFICIENT_FUNDS);
                    balance_of_usdc.write(0);
                    let usdc = IERC20Dispatcher { contract_address: self.get_usdc_address() };
                    let sent = usdc.transfer(get_caller_address(), amount);
                    assert(sent, Errors::MatchStarknetContract_INSUFFICIENT_FUNDS);
                },
                CoinPayment::STRK => {
                    let amount = balance_of_strk.read();
                    assert(amount > 0, Errors::MatchStarknetContract_INSUFFICIENT_FUNDS);
                    balance_of_strk.write(0);
                    let strk = IERC20Dispatcher { contract_address: self.get_strk_address() };
                    let sent = strk.transfer(get_caller_address(), amount);
                    assert(sent, Errors::MatchStarknetContract_INSUFFICIENT_FUNDS);
                },
                _ => { assert(false, Errors::MatchStarknetContract_UNKNOWN_PAYMENT_TYPE); },
            }
        }

        fn get_conversion_rate(self: @ContractState, request_id: u256, coin: CoinPayment) -> u256 {
            let request = self.requests.entry(request_id);
            let offer = self.offers.entry(request.read().accepted_offer_id);
            let usdc_oracle = self.price_oracles.entry(self.get_usdc_address());
            let tx_info = get_tx_info();
            match coin {
                CoinPayment::USDC => {
                    let oracle_dispatcher = IPragmaABIDispatcher {
                        contract_address: self.get_pragma_oracle_address(tx_info.chain_id),
                    };
                    let output: PragmaPricesResponse = oracle_dispatcher
                        .get_data(
                            DataType::SpotEntry(usdc_oracle.read()), AggregationMode::Median(()),
                        );
                    let usdc_amount = (offer.read().price * output.price.into()) / 10_u256.pow(10);
                    usdc_amount
                },
                _ => { 0 },
            }
        }

        fn pay_for_request_token(ref self: ContractState, request_id: u256, coin: CoinPayment) {
            let request = self.requests.entry(request_id);
            let offer = self.offers.entry(request.read().accepted_offer_id);
            let user = self.users.entry(get_caller_address());

            assert(!request.read().paid, Errors::MatchStarknetContract_REQUEST_ALREADY_PAID);
            assert(
                request.read().buyer_id == user.read().id,
                Errors::MatchStarknetContract_UNAUTHORIZED_BUYER,
            );
            match request.read().lifecycle {
                RequestLifecycle::ACCEPTED_BY_BUYER => {},
                _ => { assert(false, Errors::MatchStarknetContract_REQUEST_NOT_ACCEPTED); },
            }
            assert(
                request.read().updated_at + TIME_TO_LOCK > get_block_timestamp().into(),
                Errors::MatchStarknetContract_REQUEST_NOT_LOCKED,
            );
            assert(offer.read().is_accepted, Errors::MatchStarknetContract_REQUEST_NOT_ACCEPTED);
            request.lifecycle.write(RequestLifecycle::PAID);
            request.paid.write(true);
            let mut new_payment_info = PaymentInfo {
                authority: get_caller_address(),
                request_id: request_id,
                buyer: get_caller_address(),
                seller: offer.read().authority,
                amount: 0,
                token: coin,
                created_at: get_block_timestamp().into(),
                updated_at: get_block_timestamp().into(),
            };
            let tx_info = get_tx_info();
            match coin {
                CoinPayment::USDC => {
                    let oracle_dispatcher = IPragmaABIDispatcher {
                        contract_address: self.get_pragma_oracle_address(tx_info.chain_id),
                    };
                    let output: PragmaPricesResponse = oracle_dispatcher
                        .get_data(
                            DataType::SpotEntry(
                                self.price_oracles.entry(self.get_usdc_address()).read(),
                            ),
                            AggregationMode::Median(()),
                        );
                    let usdc_amount = (offer.read().price * output.price.into()) / 10_u256.pow(10);
                    let usdc = IERC20Dispatcher { contract_address: self.get_usdc_address() };
                    let allowance = usdc.allowance(get_caller_address(), get_contract_address());
                    let slippage_tolerance_bps = 200;
                    let min_usdc_amount = (usdc_amount * (10000 - slippage_tolerance_bps)) / 10000;
                    let max_usdc_amount = (usdc_amount * (10000 + slippage_tolerance_bps)) / 10000;
                    let mut transfer_amount = 0;
                    if allowance >= min_usdc_amount && allowance <= max_usdc_amount {
                        transfer_amount = allowance;
                    } else if allowance >= usdc_amount {
                        transfer_amount = usdc_amount;
                    } else {
                        assert(false, Errors::MatchStarknetContract_INSUFFICIENT_ALLOWANCE);
                    }
                    new_payment_info.amount = transfer_amount;
                    let sent = usdc
                        .transfer_from(
                            get_caller_address(), get_contract_address(), transfer_amount,
                        );
                    assert(sent, Errors::MatchStarknetContract_INSUFFICIENT_FUNDS);
                },
                _ => { assert(false, Errors::MatchStarknetContract_UNKNOWN_PAYMENT_TYPE); },
            }
            self.request_payment_info.entry(request_id).write(new_payment_info);
            self
                .emit(
                    RequestPaymentTransacted {
                        timestamp: get_block_timestamp().into(),
                        amount: new_payment_info.amount,
                        token: coin,
                        request_id: request_id,
                        seller_id: offer.read().seller_id,
                        buyer_id: user.read().id,
                        created_at: get_block_timestamp().into(),
                        updated_at: get_block_timestamp().into(),
                    },
                );
        }

        fn pay_for_request(ref self: ContractState, request_id: u256, coin: CoinPayment) {
            let request = self.requests.entry(request_id);
            let offer = self.offers.entry(request.read().accepted_offer_id);
            let user = self.users.entry(get_caller_address());

            assert(!request.read().paid, Errors::MatchStarknetContract_REQUEST_ALREADY_PAID);
            assert(
                request.read().buyer_id == user.read().id,
                Errors::MatchStarknetContract_UNAUTHORIZED_BUYER,
            );
            match request.read().lifecycle {
                RequestLifecycle::ACCEPTED_BY_BUYER => {},
                _ => { assert(false, Errors::MatchStarknetContract_REQUEST_NOT_ACCEPTED); },
            }
            assert(
                request.read().updated_at + TIME_TO_LOCK > get_block_timestamp().into(),
                Errors::MatchStarknetContract_REQUEST_NOT_LOCKED,
            );
            assert(offer.read().is_accepted, Errors::MatchStarknetContract_REQUEST_NOT_ACCEPTED);
            request.lifecycle.write(RequestLifecycle::PAID);
            request.paid.write(true);
            let mut new_payment_info = PaymentInfo {
                authority: get_caller_address(),
                request_id: request_id,
                buyer: get_caller_address(),
                seller: offer.read().authority,
                amount: 0,
                token: coin,
                created_at: get_block_timestamp().into(),
                updated_at: get_block_timestamp().into(),
            };
            match coin {
                CoinPayment::STRK => {
                    let strk = IERC20Dispatcher { contract_address: self.get_strk_address() };
                    let allowance = strk.allowance(get_caller_address(), get_contract_address());
                    let slippage_tolerance_bps = 200;
                    let min_strk_amount = (offer.read().price * (10000 - slippage_tolerance_bps))
                        / 10000;
                    let max_strk_amount = (offer.read().price * (10000 + slippage_tolerance_bps))
                        / 10000;
                    let mut transfer_amount = 0;
                    if allowance >= min_strk_amount && allowance <= max_strk_amount {
                        transfer_amount = allowance;
                    } else if allowance >= offer.read().price {
                        transfer_amount = offer.read().price;
                    } else {
                        assert(false, Errors::MatchStarknetContract_INSUFFICIENT_ALLOWANCE);
                    }
                    new_payment_info.amount = transfer_amount;
                    let sent = strk
                        .transfer_from(
                            get_caller_address(), get_contract_address(), transfer_amount,
                        );
                    assert(sent, Errors::MatchStarknetContract_INSUFFICIENT_FUNDS);
                },
                _ => { assert(false, Errors::MatchStarknetContract_UNKNOWN_PAYMENT_TYPE); },
            }
            self.request_payment_info.entry(request_id).write(new_payment_info);

            self
                .emit(
                    RequestPaymentTransacted {
                        timestamp: get_block_timestamp().into(),
                        amount: new_payment_info.amount,
                        token: coin,
                        request_id: request_id,
                        seller_id: offer.read().seller_id,
                        buyer_id: user.read().id,
                        created_at: get_block_timestamp().into(),
                        updated_at: get_block_timestamp().into(),
                    },
                );
        }

        fn toggle_location(ref self: ContractState) {
            let user = self.users.entry(get_caller_address());
            let location_enabled = user.read().location_enabled;
            user.location_enabled.write(!location_enabled);
        }

        fn get_location_preference(self: @ContractState, caller: ContractAddress) -> bool {
            let user = self.users.entry(caller);
            user.read().location_enabled
        }

        fn create_offer(
            ref self: ContractState,
            _price: u256,
            _request_id: u256,
            _store_name: ByteArray,
            _images: Span<ByteArray>,
        ) {
            let user = self.users.entry(get_caller_address());
            let user_num_of_stores_entry = self.user_store_ids.entry(get_caller_address());
            let user_num_of_stores = user_num_of_stores_entry.len();
            assert(
                user_num_of_stores != 0, Errors::MatchStarknetContract_STORE_NEEDED_TO_CREATE_OFFER,
            );

            match user.read().account_type {
                AccountType::BUYER => {
                    assert(false, Errors::MatchStarknetContract_ONLY_SELLERS_ALLOWED);
                },
                AccountType::SELLER => {},
                _ => { assert(false, Errors::MatchStarknetContract_INVALID_ACCOUNT_TYPE); },
            }

            let offer_count = self.offer_counter.read();
            let offer_id = offer_count + 1;
            self.offer_counter.write(offer_id);
            let new_offer = Offer {
                id: offer_id,
                price: _price,
                request_id: _request_id,
                store_name: _store_name.clone(),
                seller_id: user.read().id,
                is_accepted: false,
                created_at: get_block_timestamp().into(),
                updated_at: get_block_timestamp().into(),
                authority: get_caller_address(),
            };
            self.offers.entry(offer_id).write(new_offer);
            let mut offer_images = self.offer_images.entry(offer_id);
            let mut images = _images;
            while let Option::Some(image) = images.pop_front() {
                offer_images.append().write(image.clone());
            };

            self
                .emit(
                    OfferCreated {
                        offer_id: offer_id,
                        seller_address: get_caller_address(),
                        store_name: _store_name,
                        price: _price,
                        request_id: _request_id,
                        images: _images.into(),
                        seller_id: user.read().id,
                        seller_ids: ArrayTrait::new(),
                    },
                );
        }

        fn accept_offer(ref self: ContractState, _offer_id: u256) {
            let offer = self.offers.entry(_offer_id);
            let request = self.requests.entry(offer.read().request_id);
            let user = self.users.entry(get_caller_address());
            assert(
                user.read().id == request.read().buyer_id,
                Errors::MatchStarknetContract_UNAUTHORIZED_BUYER,
            );
            assert(!offer.read().is_accepted, Errors::MatchStarknetContract_OFFER_ALREADY_ACCEPTED);
            match request.read().lifecycle {
                RequestLifecycle::ACCEPTED_BY_BUYER => {
                    assert(
                        request.read().updated_at + TIME_TO_LOCK > get_block_timestamp().into(),
                        Errors::MatchStarknetContract_REQUEST_NOT_LOCKED,
                    );
                },
                _ => {},
            }

            offer.is_accepted.write(true);
            offer.updated_at.write(get_block_timestamp().into());
            request.locked_seller_id.write(offer.read().seller_id);
            request.sellers_price_quote.write(offer.read().price);
            request.accepted_offer_id.write(_offer_id);
            request.lifecycle.write(RequestLifecycle::ACCEPTED_BY_BUYER);
            request.updated_at.write(get_block_timestamp().into());
            let offer_seller_id = offer.read().seller_id;
            let offer_price = offer.read().price;

            self
                .emit(
                    RequestAccepted {
                        request_id: offer.read().request_id,
                        offer_id: _offer_id,
                        seller_id: offer_seller_id,
                        updated_at: get_block_timestamp().into(),
                        sellers_price_quote: offer_price,
                    },
                );
            self
                .emit(
                    OfferAccepted {
                        offer_id: _offer_id, buyer_address: get_caller_address(), is_accepted: true,
                    },
                );
        }
    }

    #[generate_trait]
    impl Private of PrivateTrait {
        fn get_strk_address(self: @ContractState) -> ContractAddress {
            contract_address_const::<
                0x4718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d,
            >()
        }
        fn get_usdc_address(self: @ContractState) -> ContractAddress {
            contract_address_const::<
                0x001d5b64feabc8ac7c839753994f469704c6fabdd45c8fe6d26ed57b5eb79057,
            >()
            // 6 decimals
        // 0x053c91253bc9682c04929ca02ed00b3e423f6710d2ee7e0d5ebb06f3ecf368a8 mainnet
        }
        fn get_eth_address(self: @ContractState) -> ContractAddress {
            contract_address_const::<
                0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7,
            >()
        }

        fn get_pragma_oracle_address(self: @ContractState, chain_id: felt252) -> ContractAddress {
            // if chain_id != 11155111 {
            //   return  contract_address_const::<
            //         0x2a85bd616f912537c50a49a4076db02c00b29b2cdc8a197ce92ed1837fa875b,
            //     >();
            // };
            contract_address_const::<
                0x36031daa264c24520b11d93af622c848b2499b66b41d611bac95e13cfca131a,
            >()
        }
    }
}

