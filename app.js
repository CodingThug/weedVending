const contractAddress = "YOUR_CONTRACT_ADDRESS"; // Replace with deployed address
const abi = []; // Paste ABI from out/WeedVending.sol/WeedVending.json after forge build
let provider, signer, contract, userAddress;

const MONAD_TESTNET = {
    chainId: "0x13DBACB3", // 1313161555 in hex
    chainName: "Monad Testnet",
    rpcUrls: ["https://testnet-rpc.monad.xyz"],
    nativeCurrency: { name: "MON", symbol: "MON", decimals: 18 },
    blockExplorerUrls: [] // Add explorer URL if available
};

async function init() {
    if (!window.ethers) {
        document.getElementById("error").innerText = "Ethers.js not loaded. Please refresh the page.";
        return;
    }

    try {
        provider = new ethers.providers.Web3Provider(window.ethereum, "any");
        contract = new ethers.Contract(contractAddress, abi, provider);

        // Add event listeners
        document.getElementById("connectWallet").addEventListener("click", connectWallet);
        document.getElementById("strainSelect").addEventListener("change", updatePrice);
        document.getElementById("amountInput").addEventListener("input", updatePrice);
        document.getElementById("buyButton").addEventListener("click", buyStrain);

        // Check network and initialize stock
        await checkNetwork();
        await updateStock();
    } catch (error) {
        document.getElementById("error").innerText = `Initialization error: ${error.message}`;
    }
}

async function checkNetwork() {
    const { chainId } = await provider.getNetwork();
    if (chainId !== parseInt(MONAD_TESTNET.chainId, 16)) {
        try {
            await window.ethereum.request({
                method: "wallet_switchEthereumChain",
                params: [{ chainId: MONAD_TESTNET.chainId }],
            });
        } catch (switchError) {
            if (switchError.code === 4902) {
                await window.ethereum.request({
                    method: "wallet_addEthereumChain",
                    params: [MONAD_TESTNET],
                });
            } else {
                document.getElementById("error").innerText = "Please switch to Monad Testnet in MetaMask";
            }
        }
    }
}

async function connectWallet() {
    try {
        document.getElementById("error").innerText = "";
        await provider.send("eth_requestAccounts", []);
        signer = provider.getSigner();
        userAddress = await signer.getAddress();
        contract = contract.connect(signer);
        document.getElementById("walletAddress").innerText = `Connected: ${userAddress.slice(0, 6)}...${userAddress.slice(-4)}`;

        const isWhitelisted = await contract.whitelist(userAddress);
        document.getElementById("buyButton").disabled = !isWhitelisted;
        if (!isWhitelisted) {
            document.getElementById("error").innerText = "You are not whitelisted to make purchases";
        } else {
            document.getElementById("error").innerText = "";
        }
    } catch (error) {
        document.getElementById("error").innerText = `Wallet connection error: ${error.message}`;
    }
}

async function updateStock() {
    try {
        document.getElementById("error").innerText = "";
        const strains = ["Sativa", "Indica", "Hybrid"];
        for (const strain of strains) {
            const stock = await contract.getStock(strain);
            document.getElementById(`${strain.toLowerCase()}Stock`).innerText = stock.toString();
            if (stock.eq(0)) {
                document.getElementById("strainSelect").querySelector(`option[value="${strain}"]`).disabled = true;
            }
        }
    } catch (error) {
        document.getElementById("error").innerText = `Error fetching stock: ${error.message}`;
    }
}

async function updatePrice() {
    const strain = document.getElementById("strainSelect").value;
    const amount = parseInt(document.getElementById("amountInput").value) || 0;
    try {
        document.getElementById("error").innerText = "";
        if (amount < 1 || !strain) {
            document.getElementById("priceDisplay").innerText = "Total: 0 ETH";
            return;
        }
        const price = await contract.getPrice(strain, amount);
        document.getElementById("priceDisplay").innerText = `Total: ${ethers.utils.formatEther(price)} ETH`;
    } catch (error) {
        document.getElementById("error").innerText = `Error calculating price: ${error.message}`;
    }
}

async function buyStrain() {
    const strain = document.getElementById("strainSelect").value;
    const amount = parseInt(document.getElementById("amountInput").value);
    try {
        document.getElementById("error").innerText = "";
        if (!signer) {
            document.getElementById("error").innerText = "Please connect your wallet first";
            return;
        }
        if (!strain || amount < 1) {
            document.getElementById("error").innerText = "Select a strain and enter a valid amount";
            return;
        }
        const stock = await contract.getStock(strain);
        if (stock.lt(amount)) {
            document.getElementById("error").innerText = `Insufficient stock for ${strain}`;
            return;
        }
        const price = await contract.getPrice(strain, amount);
        const tx = await contract.buy(strain, amount, { value: price });
        document.getElementById("error").innerText = "Transaction pending...";
        await tx.wait();
        document.getElementById("error").innerText = "Purchase successful!";
        await updateStock();
        await updatePrice();
    } catch (error) {
        document.getElementById("error").innerText = `Purchase error: ${error.message}`;
    }
}

window.addEventListener("load", init);