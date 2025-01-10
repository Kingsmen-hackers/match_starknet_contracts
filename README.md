# Match on Starknet

## Overview

Match is a decentralized platform built on the Starknet blockchain that seamlessly connects buyers and sellers, enabling a secure and efficient exchange of goods and services. Using smart contracts, Marketplace ensures transparency, reduces fraud, and provides immutable records for all transactions.

## Features

1. **User Registration**: Easily create profiles as a Buyer or Seller.
2. **Store Creation**: Sellers can create stores with custom information, including contact details and location.
3. **Request Management**: Buyers can post requests for services or products, specifying details and location.
4. **Offer Creation**: Sellers can respond to buyer requests by creating offers with pricing and images.
5. **Real-time Starknet Token Payments**: Secure and transparent payment process with USDC and STRK.
6. **Price Feeds**: Integrates Pragma for accurate conversion rates between STRK and USD.
7. **Lifecycle Events**: Requests and Offers go through stages to provide clarity on transaction status.

## Architecture

The Marketplace is developed in Solidity, utilizing:

- **Pragma Price Feeds** for STRK/USD conversion rates.
- **Smart Contract Modules** to manage user profiles, stores, requests, and offers.

## Smart Contracts

- **Marketplace Contract**: Handles the core functionalities, including user and store creation, request and offer management, and payment handling.
- **Interfaces**:
  - `IPragmaABIDispatcher`: Fetches STRK/USD price data.
  - `IERC20`: For token transfers and allowances.

## Getting Started

### Prerequisites

- **Node.js**: Recommended version >= 14.x
- **Scarb**: For local testing and deployment.
- **Rust**: Compiler version

### Installation

1. **Clone the repository**:

   ```bash
   git clone https://github.com/Kingsmen-hackers/match_starknet_contracts
   cd match_starknet_contracts
   ```

2. **Install dependencies**:

   ```bash
   npm install
   ```

3. **Configure environment variables**:
   Set up your `.env` file with the following:

   - `DEPLOYER_ADDRESS`: Your account address for Starknet network
   - `DEPLOYER_PRIVATE_KEY`: Your private key for the Starknet network.
   - `RPC_ENDPOINT` : Your rpc for starknet

4. **Compile and Deploy**:
   ```bash
   scarb build
   yarn deploy
   ```

### Usage

1. **Create a Buyer/Seller Profile**:
   Call the `create_user` function with relevant user details and account type.

2. **Create a Store (Sellers only)**:
   Sellers can call `create_store` to add a store with location data.

3. **Submit a Request (Buyers only)**:
   Buyers can submit a request by calling `create_request` with required information.

4. **Respond with an Offer (Sellers)**:
   Sellers can respond to a request by calling `create_offer`, linking it to a request.

### Events

- **UserCreated**: Triggered when a new user is registered.
- **StoreCreated**: Triggered upon new store creation.
- **RequestCreated**: Triggered when a buyer submits a request.
- **OfferCreated**: Triggered when a seller submits an offer.
- **RequestPaymentTransacted**: Records each payment transaction.

### Testing

Run tests to ensure contract functionality:

```bash
scarb test
```

## Challenges & Future Enhancements

- **Token Selection Flexibility**: Allow users to choose from a variety of stablecoins for payment.

## Contributors

- **David** - Blockchain Developer [Davyking](https://github.com/Imdavyking)
- **Favour** - Frontend Developer [Sire](https://github.com/favourwright)

## License

This project is licensed under the MIT License.
