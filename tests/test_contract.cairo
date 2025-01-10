use snforge_std::{
    declare, ContractClassTrait, DeclareResultTrait, start_cheat_caller_address,
    stop_cheat_caller_address,
};
use match_starknet_contracts::{IMatchStarknetContractDispatcher};
use starknet::ContractAddress;


#[test]
fn test_add_point_from_weight() {
    let erc20_contract = declare("ERC20").unwrap().contract_class();
    let mut constructor_calldata = ArrayTrait::new();
    erc20_contract.class_hash.serialize(ref constructor_calldata);
    let contract = declare("LifeSourceManager").unwrap().contract_class();
    let (contract_address, _) = contract.deploy(@constructor_calldata).unwrap();

    let _ = IMatchStarknetContractDispatcher { contract_address };
    let user: ContractAddress = starknet::contract_address_const::<'USER'>();
    start_cheat_caller_address(contract_address, user);
    // test
    stop_cheat_caller_address(contract_address);
    // assert(true, 'Invalid user');
}
