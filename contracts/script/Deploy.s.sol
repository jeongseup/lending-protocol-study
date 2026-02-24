// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/LendingPool.sol";
import "../src/InterestRateModel.sol";
import "../src/PriceOracle.sol";

/// @title 배포 스크립트 — Day 5/7 학습
/// @notice 미니 렌딩 프로토콜을 테스트넷에 배포합니다
/// @notice Deploy mini lending protocol to testnet
/// @dev 실행 방법 / How to run:
/// @dev forge script script/Deploy.s.sol --rpc-url sepolia --broadcast --verify

contract DeployScript is Script {
    function run() external {
        // 배포자 개인키 로드 / Load deployer private key
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerKey);

        // 1. 가격 오라클 배포 / Deploy price oracle
        // 최대 지연 1시간 / Max staleness 1 hour
        PriceOracle oracle = new PriceOracle(3600);
        console.log("PriceOracle deployed at:", address(oracle));

        // 2. 이자율 모델 배포 / Deploy interest rate model
        InterestRateModel rateModel = new InterestRateModel(
            0.02e18,  // 2% 기본 이자율 / 2% base rate
            0.1e18,   // kink 이하 10% 기울기 / 10% slope below kink
            1.0e18,   // kink 이상 100% 기울기 / 100% slope above kink
            0.8e18    // 80% kink / 80% optimal utilization
        );
        console.log("InterestRateModel deployed at:", address(rateModel));

        // 3. 렌딩 풀 배포 / Deploy lending pool
        LendingPool pool = new LendingPool(address(oracle), address(rateModel));
        console.log("LendingPool deployed at:", address(pool));

        // 4. 리저브 초기화 (테스트넷 토큰 주소 필요)
        //    Initialize reserves (testnet token addresses needed)
        //
        // Sepolia 테스트넷 토큰 예시:
        // Sepolia testnet token examples:
        //
        // address WETH = 0x...; // Sepolia WETH
        // address USDC = 0x...; // Sepolia USDC
        //
        // oracle.setPriceFeed(WETH, CHAINLINK_ETH_USD_FEED);
        // oracle.setPriceFeed(USDC, CHAINLINK_USDC_USD_FEED);
        //
        // pool.initReserve(WETH, 0.75e18, 0.80e18);  // 75% CF, 80% LT
        // pool.initReserve(USDC, 0.80e18, 0.85e18);  // 80% CF, 85% LT

        vm.stopBroadcast();

        // 배포 요약 / Deployment summary
        console.log("\n=== Deployment Summary ===");
        console.log("Oracle:          ", address(oracle));
        console.log("Rate Model:      ", address(rateModel));
        console.log("Lending Pool:    ", address(pool));
        console.log("========================\n");
    }
}
