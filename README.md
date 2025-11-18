# BUND/MATIC LP Staking

This repository contains a Hardhat-based smart contract suite implementing the **LP staking mechanism for the BUND token** on the Polygon network.  
The system integrates directly with **Uniswap V2** to automate liquidity provisioning and streamline staking flows for the BUND/MATIC pool.

---

## Overview

The primary contract, `BUNDLPStaking`, manages user staking, reward distribution, and automated LP creation for the BUND/MATIC Uniswap V2 pair.

---

## Functionality

### **Stake**
Allows users to **directly stake** their existing BUND/MATIC LP tokens.

### **addAndStake**
Provides automated **Uniswap V2 liquidity provisioning** using user-supplied tokens.  
The minted LP tokens are staked on behalf of the user.

### **swapAddAndStake**
Accepts MATIC, swaps **half into BUND**, and uses the resulting token pair to create liquidity through Uniswap V2.  
The generated LP tokens are automatically staked.

### **Exit**
Withdraws **all staked LP tokens** and returns both the principal and accumulated rewards to the user.
