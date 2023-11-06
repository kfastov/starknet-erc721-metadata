# NFT Smart Contract for Starknet

This repository contains a smart contract designed for the Starknet blockchain, tailored for managing non-fungible tokens (NFTs) with a linkage to IPFS for metadata storage.

## Prerequisites

To build and deploy this smart contract on Starknet, you will need the following tools:

- **Starkli**: Command-line tool for Starknet to compile and deploy your contracts.
  - Installation guide: [Starkli Installation](https://book.starkli.rs/installation)

- **Scarb**: The build toolchain and package manager for Cairo and Starknet ecosystems.
  - Installation guide: [Scarb Installation](https://docs.swmansion.com/scarb/download.html)
  - Account creation: [Accounts](https://book.starkli.rs/accounts)

Please follow the linked guides to install each necessary component before attempting to build or deploy the smart contract.

## Non-Standard Methods

In addition to the standard ERC721 methods, this contract implements a few non-standard methods for enhanced functionality:

- `mint`: A method to mint new NFTs, restricted to be called by the contract's admin only. It allows batch minting up to a defined `MAX_MINT_AMOUNT`.

- `max_supply`: Retrieves the maximum supply of tokens that can be minted.

- `total_supply`: Provides the total number of tokens that have been minted.

- `set_base_uri`: Sets a base URI that will be common for all tokens. .


## Build and deploy

  To deploy this smart contract to Starknet, you will use `starkli` to declare the contract class and deploy its instances on Starknet after compiling the contract with `Scarb`.

  ### Build the contract:

  ```shell
  scarb build
  ```

  ### Declare the contract:

  ```shell
  starkli declare target/dev/erc721_ipfs_example_ERC721IPFSTemplate.contract_class.json
  ```

  ### Deploy the contract with constructor args:

  ```shell
  starkli deploy {{CONTRACT_CLASS_HASH}} {{admin_account_address}} {{name}} {{symbol}} {{max_supply}}
  ```

## Contributing
Contributions of all kinds are welcome.
If you want to tip me a beer, you can send me some ETH to [0x02dc32837907CA92B5B99e7C2470fFF9c62FAB91F2cc1Ef1416A07171F1eF8C5](https://starkscan.co/contract/0x02dc32837907ca92b5b99e7c2470fff9c62fab91f2cc1ef1416a07171f1ef8c5)