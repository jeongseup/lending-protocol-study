# Day 3: 청산 + Foundry 테스팅 심화
# Day 3: Liquidation + Foundry Testing Deep Dive

## 청산 메커니즘 / Liquidation Mechanism

### 청산 흐름 / Liquidation Flow
```
1. 가격 하락 → HF < 1
   Price drops → HF < 1

2. 청산자가 부채 일부 상환 (최대 50% = Close Factor)
   Liquidator repays partial debt (max 50% = Close Factor)

3. 청산자가 담보 + 보너스(5-10%) 수령
   Liquidator receives collateral + bonus (5-10%)

4. 차입자의 부채 감소
   Borrower's debt decreases
```

#### 구체적 예시 (Scenario.t.sol 기준)
```
Alice: 10 ETH 담보 ($20,000), 15,000 USDC 대출
ETH 가격 $2,000 → $1,500 하락 → HF = 0.80

Liquidator가 7,500 USDC 상환 (Close Factor 50%)
→ 5.25 ETH 수령 (= 7,500 × 1.05 / 1,500, 5% 보너스 포함)
→ 순이익 $375

Alice 청산 후: 4.75 ETH 담보, 7,500 USDC 부채, HF = 0.76
```

### Close Factor — 청산 비율 제한
- 한 번에 최대 50%만 청산 가능
- 이유: 차입자에게 담보 추가/부채 상환 기회, 대량 담보 매각 방지

### 청산자 생태계 / Liquidator Ecosystem
- **오픈 마켓**: 프로토콜이 운영하는 것이 아님, 누구나 참여 가능
- **대부분 자동화 봇**: MEV searcher들이 24/7 모니터링
- **Flash Loan 청산**: 자본금 0으로 청산 가능 (빌려서 → 청산 → 보너스 수령 → 상환)
- **청산자가 없으면?**: Bad Debt 발생 → 담보 < 부채 → 예치자 손실 위험
- **Bad Debt 방어**: Aave Safety Module, Maker MKR 경매, Euler Dutch Auction 등

> 심화: [deep-dive/liquidation-mechanics.md](deep-dive/liquidation-mechanics.md)

## Foundry 테스팅 패턴 / Foundry Testing Patterns

### 1. 포크 테스팅 / Fork Testing
- `vm.createSelectFork()` — 메인넷 상태를 복제
- 실제 Aave V3 컨트랙트와 상호작용 가능
- `test/AaveFork.t.sol` 참조

### 2. 퍼즈 테스팅 / Fuzz Testing
- `testFuzz_` 접두사 + `bound()` 사용
- 랜덤 입력으로 엣지 케이스 발견
- `test/InterestRate.fuzz.t.sol` 참조

### 3. 불변성 테스팅 / Invariant Testing
- `invariant_` 접두사
- 랜덤 함수 호출 시퀀스 후 조건 확인
- `test/LendingPool.invariant.t.sol` 참조

### 4. 시나리오 테스팅 / Scenario Testing
- `vm.warp()` — 시간 경과 시뮬레이션
- `vm.mockCall()` — 오라클 가격 조작
- `test/Liquidation.t.sol` 참조

## 할 일 / TODO
- [x] 가이드 섹션 6 읽기 / Read guide Section 6
- [ ] Aave 청산 문서 읽기 / Read Aave liquidation docs
- [ ] 포크 테스트 실행 (RPC URL 필요) / Run fork tests (needs RPC URL)
- [x] 전체 수명주기 시나리오 테스트 작성 / Write full lifecycle scenario tests
