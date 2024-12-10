import React, { useState } from 'react';
import { ethers } from 'ethers';
import Web3Modal from 'web3modal';
// import WalletConnectProvider from "@walletconnect/web3-provider";

const App = () => {
  const [totalSupply, setTotalSupply] = useState(null);
  const [provider, setProvider] = useState(null);
  const [signer, setSigner] = useState(null);
  const [account, setAccount] = useState(null);
  const [balance, setBalance] = useState(null);

  const web3Modal = new Web3Modal({
    cacheProvider: true,
    providerOptions: {
      metamask: {
        package: true,
      },
      // walletconnect: {
      //   package: WalletConnectProvider, // Używa WalletConnect
      //   options: {
      //     rpc: {
      //       1: "https://mainnet.infura.io/v3/YOUR_INFURA_PROJECT_ID", // Główna sieć Ethereum
      //       137: "https://polygon-rpc.com", // Polygon
      //       31337: "http://127.0.0.1:8545", // Lokalny Ganache
      //       123: "https://rpc.pulsechain.com", // RPC PulseChain mainnet
      //     },
      //   },
      // },
    },
  });

  const connectWallet = async () => {
    const instance = await web3Modal.connect();
    const ethersProvider = new ethers.providers.Web3Provider(instance);

    const currentSigner = ethersProvider.getSigner();
    const address = await currentSigner.getAddress();
    const balance = await currentSigner.getBalance();
    setProvider(ethersProvider);
    setSigner(currentSigner);
    setAccount(address);
    setBalance(ethers.utils.formatEther(balance)); // Wyświetlenie salda w ETH
  };

  const disconnectWallet = () => {
    web3Modal.clearCachedProvider();
    setProvider(null);
    setSigner(null);
    setAccount(null);
    setBalance(null);
  };

  const contractAddress = "0x583e869b26ae42da12ab003201908757959cd397";
  const abi = [
    "function totalSupply() view returns (uint256)"
  ];

  const getTotalSupply = async () => {
    try {
      const provider = new ethers.providers.JsonRpcProvider("http://127.0.0.1:8545");

      const contract = new ethers.Contract(contractAddress, abi, provider);

      const supply = await contract.totalSupply();
      setTotalSupply(ethers.utils.formatUnits(supply, 18));
    } catch (error) {
      console.error("Błąd podczas odczytu totalSupply:", error);
    }
  };

  return (
      <div className="container">
        <h1>Total Supply: {totalSupply}</h1>
        <button onClick={getTotalSupply}>Show Total Supply</button>

        {!account ? (
            <button className="button" onClick={connectWallet}>Connect Wallet</button>
        ) : (
            <div>
              <p><strong>Adres:</strong> {account}</p>
              <p><strong>Saldo:</strong> {balance} ETH</p>
              <button className="button" onClick={disconnectWallet}>Odłącz portfel</button>
            </div>
        )}
      </div>

  );
};

export default App;
