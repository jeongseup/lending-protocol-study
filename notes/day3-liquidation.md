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

### Close Factor — 청산 비율 제한
- 한 번에 최대 50%만 청산 가능
- Maximum 50% liquidatable per call
- 이유: 과도한 청산 방지 + 시장 안정
- Reason: Prevent excessive liquidation + market stability

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
- [ ] 가이드 섹션 6 읽기 / Read guide Section 6
- [ ] Aave 청산 문서 읽기 / Read Aave liquidation docs
- [ ] 포크 테스트 실행 (RPC URL 필요) / Run fork tests (needs RPC URL)
- [ ] 전체 수명주기 시나리오 테스트 작성 / Write full lifecycle scenario tests
