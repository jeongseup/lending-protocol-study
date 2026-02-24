# Day 2 Review — 오늘 배운 것 정리

> 2026-02-24 (월) 학습 리뷰

---

## 완료한 항목 / Completed

- [x] Compound V2 심화 학습 마무리 (Day 1에서 이어짐)
- [x] JumpRateModel 구현 및 테스트 — 18개 단위 + 6개 퍼즈 테스트 통과
- [x] Alberto Cuesta 아티클 읽기 → lending-protocol-types.md 작성
- [x] Compound V2 vs Aave V3 vs Euler 비교 → pool-lending-comparison.md 작성
- [x] Aave V3 코드 분석 (aave-v3-origin 기반) → aave-v3-code-reading.md 문서화
- [x] LendingPool.sol 스토리지를 Aave V3 PoolStorage 패턴으로 리팩토링
- [x] defi-lending-protocol-guide.md — Stable Rate 삭제 반영 업데이트

---

## 핵심 개념 요약 / Key Concepts Learned

### 1. 프로토콜 아키텍처 유형 3가지

```
① Pool-based (Compound, Aave)
   → 예치자 → 공유 풀 → 대출자
   → 이자율은 사용률로 자동 결정
   → 장점: 유동성 효율, 단점: 시스템 리스크 공유

② CDP (MakerDAO)
   → 담보 예치 → 스테이블코인(DAI) 직접 발행
   → 이자율은 거버넌스가 결정 (Stability Fee)
   → 장점: 거버넌스 통제, 단점: 자산 제한

③ Fixed-rate / P2P (Notional, Morpho)
   → 기간/이자율 고정 또는 1:1 매칭
   → 장점: 예측 가능, 단점: 유동성 파편화
```

### 2. Aave V3 vs Compound V2 핵심 차이

```
                Compound V2            Aave V3 (aave-v3-origin)
아키텍처        CToken = 풀+토큰        Pool + aToken/debtToken 분리
스토리지        시장별 CToken 컨트랙트   _reserves mapping (한 컨트랙트)
사용자 상태     enterMarkets[] 배열     UserConfigurationMap 비트맵
코드 구조       단일 파일 (monolithic)   Logic 라이브러리 분리 (modular)
업그레이드      불가                    Proxy (TransparentUpgradeableProxy)
소수점 정밀도   Mantissa (1e18)         Ray (1e27) + Wad (1e18)
```

### 3. UserConfigurationMap 비트맵

```
Aave V3에서 가장 인상적인 가스 최적화 패턴:

  uint256 data 하나에 모든 리저브 상태를 비트로 저장

  리저브 0: [bit 0 = isCollateral, bit 1 = isBorrowing]
  리저브 1: [bit 2 = isCollateral, bit 3 = isBorrowing]
  리저브 n: [bit 2n = isCollateral, bit 2n+1 = isBorrowing]

  최대 128개 리저브 (256비트 / 2비트) — SSTORE 1번으로 관리

  HF 계산 시 비트맵으로 미사용 리저브 스킵 → 루프 최적화
  vs enterMarkets[] 배열: 동적 배열 순회 → 가스 비쌈
```

### 4. Aave V3 PoolStorage 3대 매핑

```
우리 코드에도 적용한 핵심 패턴:

  ① mapping(address => ReserveData) _reserves
     → 토큰 주소 → 리저브 설정/상태
     → 기존 Market struct를 ReserveData로 변환

  ② mapping(address => UserConfigurationMap) _usersConfig
     → 사용자 주소 → 비트맵 (담보/대출 상태)
     → 기존 배열 기반 조회를 비트 연산으로 교체

  ③ mapping(uint256 => address) _reservesList + uint16 _reservesCount
     → 리저브 ID → 토큰 주소 (순회용)
     → 기존 address[] assetList를 mapping으로 변환
     → 배열보다 가스 효율적 (동적 크기 변경 없음)
```

### 5. Stable Rate는 왜 삭제됐는가

```
Aave V3.2 (2024)에서 공식 제거:

  ① 악용 가능: 낮은 고정금리로 빌린 뒤 시장 이자율 오르면 부당 이득
  ② 복잡성: Variable + Stable 이중 관리 → 코드/감사 비용 증가
  ③ 낮은 사용률: DeFi 사용자 대부분 단기 차입 → 변동금리 선호
  ④ 거버넌스 부담: sToken 관련 파라미터까지 관리해야 함

  결과: Variable-only로 단순화 + IRS를 Pool-level immutable로 통합
  → 가스 절약 + 코드 단순화 + 감사 범위 축소
```

---

## Q&A 정리 / Questions & Answers

### Q1. Compound V2의 "Fresh" 패턴이란?

```
A: 이자를 먼저 정산한 뒤에야 핵심 로직을 실행하는 패턴.

  mint() → mintInternal(accrueInterest 먼저!) → mintFresh(실제 로직)
  borrow() → borrowInternal(accrueInterest) → borrowFresh(실제 로직)

  왜?
  → 이자가 미정산되면 borrowIndex가 옛날 값
  → 그 상태에서 deposit/borrow하면 회계가 꼬임
  → 그래서 "Fresh"한 상태에서만 실행

  우리 코드의 _accrueInterest() 호출도 같은 원리:
    function deposit(...) { _accrueInterest(asset); ... }
    function borrow(...) { _accrueInterest(asset); ... }
```

### Q2. Mantissa(1e18) vs Ray(1e27) — 왜 다른 정밀도?

```
A: 복리 이자 계산의 정밀도 차이.

  Compound: Mantissa = 1e18 (= Solidity 기본 단위)
    → 블록당 이자율 ≈ 0.000000003... → 18자리로 충분
    → 간단하고 직관적

  Aave: Ray = 1e27 (= 10^27)
    → 초 단위 이자율 ≈ 더 작은 수 → 정밀도 부족 방지
    → exponentiation 과정에서 반올림 오차 누적 방지
    → WadRayMath 라이브러리로 연산

  현실적 차이: 대부분 상황에서 무시할 수준
  → 하지만 TVL $10B+ 프로토콜에서는 1e-18 오차도 $$
```

### Q3. reservesList를 왜 배열이 아닌 mapping으로?

```
A: 가스 효율 + 삭제 시 문제 회피.

  배열 (address[]):
    → 중간 삭제 시 배열 재정렬 필요 (O(n) 가스)
    → 또는 빈 슬롯 남기면 순회 시 체크 필요
    → push/pop으로 길이 변경 시 SSTORE 추가

  매핑 (mapping(uint256 => address)):
    → 고정 슬롯: reservesList[0] = WETH, reservesList[1] = USDC
    → reservesCount만 관리하면 순회 가능
    → 삭제: reservesList[id] = address(0)으로 무효화 (cheap)
    → Aave V3는 최대 128개 리저브 제한 (비트맵 256비트 / 2)
```

---

## 우리 코드 리팩토링 요약 / Code Refactoring Summary

### Before → After

```solidity
// BEFORE (v1)
struct Market { ... }
mapping(address => Market) public markets;
address[] public assetList;
modifier marketExists(address asset) { ... }
function addMarket(...) external onlyOwner { ... }

// AFTER (Aave V3 style)
struct ReserveData { ..., uint16 id, ... }         // +id 필드
struct UserConfigurationMap { uint256 data; }       // 비트맵
mapping(address => ReserveData) public reserves;
mapping(address => UserConfigurationMap) internal _usersConfig;
mapping(uint256 => address) public reservesList;
uint16 public reservesCount;
modifier reserveActive(address asset) { ... }
function initReserve(...) external onlyOwner { ... }
```

### 비트맵 헬퍼 함수 / Bitmap Helpers

```solidity
// 비트 읽기 / Read bits
_isUsingAsCollateral(config, reserveId) → bool
_isBorrowing(config, reserveId) → bool

// 비트 쓰기 / Write bits
_setUsingAsCollateral(config, reserveId, using) → config
_setBorrowing(config, reserveId, borrowing) → config
```

### 테스트 결과 / Test Results

```
리팩토링 전: 61 tests passed, 0 failed, 2 skipped
리팩토링 후: 62 tests passed, 0 failed, 2 skipped  (+1 bitmap test)

  AaveForkTest             | 2 passed | 2 skipped
  InterestRateFuzzTest     | 6 passed |
  JumpRateModelTest        | 18 passed |
  LendingPoolInvariantTest | 2 passed |
  LendingPoolTest          | 15 passed |  ← was 14, +1 bitmap test
  LiquidationTest          | 6 passed |
  OracleTest               | 13 passed |
```

---

## 오늘의 핵심 인사이트 / Key Insights

```
1. Aave V3 = Compound V2의 아키텍처 진화
   → CToken(풀+토큰 일체형) → Pool + Token 분리
   → 배열 순회 → 비트맵 스킵
   → 블록 단위 → 초 단위 이자 계산
   → 단일 컨트랙트 → Logic 라이브러리 분리

2. 비트맵은 DeFi의 핵심 가스 최적화 패턴
   → uint256 하나로 128개 리저브 상태 관리
   → SSTORE 1번 vs 배열 N번
   → HF 계산 루프에서 미사용 리저브 O(1) 스킵
   → 우리 코드에도 적용: deposit/borrow/repay/liquidate 모두 비트맵 관리

3. "스토리지 레이아웃이 곧 아키텍처"
   → Aave V3의 3대 매핑이 전체 구조를 결정
   → reserves: 자산별 설정, usersConfig: 사용자별 상태, reservesList: 순회용
   → 이 구조를 이해하면 나머지 로직은 자연스럽게 따라옴

4. Stable Rate 삭제는 "단순화 > 기능"의 교훈
   → 기능이 많다고 좋은 게 아님
   → 사용되지 않는 기능 = 공격 표면 + 감사 비용 + 거버넌스 부담
   → V3.2에서 과감히 삭제 → 코드 품질 향상

5. 프로토콜 유형 이해가 먼저
   → Pool-based, CDP, Fixed-rate — 각각 트레이드오프가 다름
   → DevOps 관점: 모니터링 포인트, 리스크 시나리오, 인프라 요구사항이 다름
   → Pool-based가 DeFi 메인스트림 (Aave, Compound, Euler)
```

---

## 생성된 심화 문서 / Deep Dive Documents Created

| 문서 | 핵심 내용 |
|------|----------|
| [compound-v2-code-reading.md](deep-dive/compound-v2-code-reading.md) | Q&A 본문 통합, Architecture Overview 확장, 오라클/청산봇 통합 |
| [compound-v2-scenario.md](deep-dive/compound-v2-scenario.md) | Kink 설명, 실제 코드 매핑 계산, totalBorrows 분리 저장 |
| [lending-protocol-types.md](deep-dive/lending-protocol-types.md) | Pool-based vs CDP vs Fixed-rate 유형 비교 |
| [pool-lending-comparison.md](deep-dive/pool-lending-comparison.md) | Compound V2 vs Aave V3 vs Euler 시나리오 비교 |
| [aave-v3-code-reading.md](deep-dive/aave-v3-code-reading.md) | Aave V3 코드 리딩 가이드 (aave-v3-origin 기반) |

---

## 내일 할 것 / Tomorrow (Day 3)

```
Day 3: 청산 + Foundry 테스트 심화
Day 3: Liquidation + Foundry Testing Deep Dive

  오전: 청산 이론
    - 가이드 섹션 6 읽기 (Liquidation)
    - Aave 청산 문서 읽기
    - Health Factor < 1 → 청산 흐름 완전 이해

  오후: Foundry 테스트 패턴
    - Fork Testing — 메인넷 Aave V3 포크 상호작용 (이미 기본 구현됨)
    - Fuzz Testing — 이자율 엣지 케이스 (이미 구현됨)
    - Invariant Testing — 풀 불변성 (이미 구현됨)
    - Scenario Testing — 전체 라이프사이클 시나리오

  저녁: 시나리오 테스트 작성
    1. Deposit → Borrow → Time → Interest → Repay
    2. Deposit → Borrow → Price Drop → HF < 1 → Liquidation
    3. Flash Loan → Arbitrage → Repay (같은 tx)

  참고: 테스트의 상당 부분은 이미 작성됨 → 리뷰 + 보강에 집중
```
