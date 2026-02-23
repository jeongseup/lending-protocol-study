# Deposit Tokens 심화 — aToken vs cToken
# Deposit Tokens Deep Dive — aToken vs cToken

> 예치 영수증 토큰의 동작 방식 비교
> Comparing how deposit receipt tokens work internally

---

## 공통점 — 둘 다 "예치 영수증"

```
역할은 동일: 예치하면 받는 토큰, 나중에 돌려주면 원금+이자를 회수
Common role: Receipt token for deposits, redeem for principal + interest

User → deposit(1,000 USDC) → Pool → Mint receipt token → User
User → redeem(receipt token) → Pool → Return USDC + interest → User
```

---

## 핵심 차이 — "이자를 어떻게 반영하느냐"

```
┌─────────────┬──────────────────────────────────────────┐
│ cToken      │ 토큰 수량 고정, 교환비율이 올라감          │
│ (Compound)  │ Balance stays same, exchange rate grows   │
│             │                                          │
│             │ 예치: 1,000 USDC → 50,000 cUSDC 발행     │
│             │       (교환비율 0.02)                      │
│             │ 1년후: 50,000 cUSDC 그대로                │
│             │       교환비율 0.025로 상승               │
│             │ 인출: 50,000 × 0.025 = 1,250 USDC 회수   │
├─────────────┼──────────────────────────────────────────┤
│ aToken      │ 토큰 수량이 자동으로 늘어남 (rebase)      │
│ (Aave)      │ Balance itself increases over time        │
│             │                                          │
│             │ 예치: 1,000 USDC → 1,000 aUSDC 발행      │
│             │       (1:1 비율)                          │
│             │ 1년후: 지갑에 1,050 aUSDC로 늘어남         │
│             │ 인출: 1,050 aUSDC → 1,050 USDC 회수      │
└─────────────┴──────────────────────────────────────────┘
```

---

## 사용자 경험 차이 / UX Difference

```
cToken: "내 잔고가 50,000인데... 이게 지금 얼마지?"
        → 교환비율을 곱해야 실제 가치를 알 수 있음
        → 계산이 필요해서 직관적이지 않음

aToken: "내 잔고가 1,050이네, 50 USDC 이자 붙었구나"
        → 잔고 = 실제 가치 (1:1)
        → 직관적, 지갑에서 바로 확인 가능

그래서 Aave가 UX 측면에서 더 직관적이라는 평가를 받음
Aave is generally considered more intuitive for end users
```

---

## 기술적 구현 / Technical Implementation

```
cToken (교환비율 방식 / Exchange Rate Model):

  exchangeRate = (totalCash + totalBorrows - totalReserves) / totalSupply

  - 비율이 단조증가 (이자가 누적되면서)
  - Exchange rate monotonically increases as interest accrues
  - ERC20 표준 그대로 사용 가능 (transfer 정상 작동)
  - Standard ERC20 — transfer works normally

  deposit:  cTokenAmount = depositAmount / exchangeRate
  redeem:   underlyingAmount = cTokenAmount × exchangeRate
```

```
aToken (리베이스 방식 / Rebase Model):

  balanceOf(user) = scaledBalance × liquidityIndex

  - balanceOf()를 override해서 실시간으로 이자 반영
  - Overrides balanceOf() to reflect interest in real-time
  - 내부적으로 scaled balance + liquidity index로 계산
  - Internally uses scaled balance + liquidity index

  deposit:  scaledBalance = depositAmount / currentIndex
  balanceOf: return scaledBalance × currentIndex  (항상 최신 이자 반영)
```

---

## 장단점 비교 / Trade-offs

```
┌──────────┬────────────────────────┬────────────────────────┐
│          │ cToken (Compound)      │ aToken (Aave)          │
├──────────┼────────────────────────┼────────────────────────┤
│ 직관성    │ ✗ 교환비율 계산 필요    │ ✓ 잔고 = 실제 가치     │
│ UX       │ ✗ Needs rate calc      │ ✓ Balance = value      │
├──────────┼────────────────────────┼────────────────────────┤
│ 호환성    │ ✓ 표준 ERC20           │ ✗ rebase라 일부 DeFi와 │
│ Compat.  │ ✓ Standard ERC20       │   호환 문제 가능       │
├──────────┼────────────────────────┼────────────────────────┤
│ DeFi     │ ✓ DEX/Vault에서        │ ✗ rebase 미지원 프로토콜│
│ 조합성    │   바로 사용 가능       │   에서 이자 손실 가능   │
│ Compos.  │ ✓ Works in DEX/Vaults  │ ✗ May lose interest in │
│          │                        │   non-rebase protocols │
├──────────┼────────────────────────┼────────────────────────┤
│ 가스비    │ ✓ 단순한 계산          │ ✗ index 조회 필요      │
│ Gas      │ ✓ Simple calculation   │ ✗ Needs index lookup   │
└──────────┴────────────────────────┴────────────────────────┘

실제 트렌드 / Actual trend:
  - Aave V3: aToken 유지 (UX 우선)
  - Compound V3 (Comet): cToken 폐지, 내부 잔고 직접 관리
  - ERC-4626: "Tokenized Vault" 표준 — cToken 방식을 표준화한 것
    → 업계가 교환비율 방식을 표준으로 수렴하는 추세
```

---

## 수학적으로 동일 — "언제 곱하느냐"만 다름

```
cToken:  amount = shares × exchangeRate      (인출할 때 곱셈)
aToken:  balance = scaledBalance × index     (조회할 때 곱셈)

결과는 같음 — 곱셈 시점만 다름!
Same result — only the timing of multiplication differs!

cToken: 인출 시점에 곱셈 → 사용자가 직접 계산해야 실제 가치를 앎
aToken: 조회 시점에 곱셈 → 지갑에서 바로 실제 가치가 보임
```

**aToken 내부 동작 상세:**

```
aToken의 balanceOf()는 이렇게 override 됨:

  // 저장된 값 (예치 시점에 고정)
  scaledBalance = 1000

  // 실시간으로 계산
  function balanceOf(user) {
    return scaledBalance × liquidityIndex / userIndex
  }

  예치 시점: liquidityIndex = 1.00
    → balanceOf = 1000 × 1.00 / 1.00 = 1,000 aUSDC

  1년 후: liquidityIndex = 1.05 (이자 5% 누적)
    → balanceOf = 1000 × 1.05 / 1.00 = 1,050 aUSDC

  실제로 토큰이 추가 mint 되는 게 아님!
  balanceOf()가 호출될 때마다 계산해서 보여주는 것
  No actual minting — calculated on every balanceOf() call
```

---

## Walrus 스테이킹과 cToken — 같은 패턴

```
핵심 패턴: "Share-Based Accounting" (지분 기반 회계)

┌──────────────────────────────────────────────────────────┐
│  1. 풀에 총 자산과 총 지분이 있음                          │
│  2. 예치: 자산 → 현재 비율로 지분 변환                     │
│  3. 시간 경과: 총 자산 증가 (이자/보상), 총 지분은 그대로   │
│  4. 인출: 지분 → 새로운(더 높은) 비율로 자산 변환          │
│  5. 차이 = 수익                                          │
└──────────────────────────────────────────────────────────┘
```

**나란히 비교:**

```
Compound cToken:
  exchange_rate = (totalCash + totalBorrows - totalReserves) / totalSupply
  deposit:  shares = amount / exchange_rate        (ETH → cETH)
  withdraw: amount = shares × exchange_rate        (cETH → ETH)

Walrus StakingPool:
  exchange_rate = total_wal / total_shares
  stake:    shares = principal × total_shares / total_wal
  withdraw: amount = shares × total_wal / total_shares

  → 같은 공식, 변수명만 다름!
```

**구체적 숫자 비교:**

```
Compound 예시:
  예치: 10 ETH / 0.02 = 500 cETH
  시간 경과: exchange_rate 0.02 → 0.02103456
  인출: 500 cETH × 0.02103456 = ~10.05 ETH
  수익: ~0.05 ETH

Walrus 예시:
  스테이킹: 1,000,000,000 WAL → 999,922,610 shares
           (e4 rate: 6710485646776390 / 6709966322808817)
  시간 경과: rate 변동 (리워드 누적)
  인출: 999,922,610 shares → 1,000,217,678 WAL
           (e8 rate: 6705234809326492 / 6703256739865348)
  수익: 217,678 WAL
```

**이 패턴을 쓰는 프로토콜들:**

```
DeFi Lending:
  Compound cToken     ← 원조 (2019)
  ERC-4626            ← cToken 패턴을 ERC 표준으로 (2022)

Liquid Staking:
  Lido wstETH         ← wrapped stETH가 이 패턴
  Rocket Pool rETH    ← exchange rate 방식
  Walrus StakingPool  ← 동일한 share 기반 회계

공통 이유: "토큰 수량을 바꾸지 않고 가치를 반영"하는 가장 깔끔한 방법
         rebase(잔고 자체를 바꾸는 것)보다 ERC20 호환성이 좋음

참고: Lido의 stETH는 rebase 방식 (aToken과 유사)
     wstETH는 wrapped 버전으로 share 방식 (cToken과 유사)
     → 하나의 프로토콜이 두 방식을 모두 제공하는 사례
```

---

## Borrow APR vs Supply APY — 왜 항상 Borrow > Supply?

```
Supply APY = Borrow APR × Utilization × (1 - Reserve Factor)

Utilization < 1 이고, (1 - RF) < 1 이니까:
Supply = Borrow × (1보다 작은 수) × (1보다 작은 수)
       → Supply는 무조건 Borrow보다 작음

이유:
① 풀의 돈이 100% 빌려진 게 아님 (Utilization < 100%)
   → 안 빌려간 돈은 이자를 안 벌음
② 프로토콜이 중간에 떼감 (Reserve Factor)
   → 대출자가 낸 이자의 일부가 프로토콜 금고로

단, Layer 2 (토큰 인센티브)까지 포함하면 역전 가능:
  2020 DeFi Summer: COMP 보상 > 대출 이자 → "빌리면 돈 버는" 상황
  하지만 이건 기본 이자 구조의 역전이 아니라 외부 인센티브 때문
```

---

## Variable Rate vs Stable Rate (Aave)

```
Compound:
  Borrow: Variable APR만 (사용률에 따라 실시간 변동)
  Supply: Variable APY만

Aave:
  Borrow: Variable APR + Stable APR (두 가지 옵션)
  Supply: Variable APY만

Stable Rate = 빌리는 시점의 이자율을 "고정"하는 옵션
  Variable: 오늘 5% → 내일 8% → 모레 3% (계속 변동)
  Stable:   빌릴 때 6%로 고정 → 6% → 6% → 6%

현실 비유:
  Variable = 변동금리 주택담보대출
  Stable   = 고정금리 주택담보대출 (약간 더 비쌈)
```

**Stable Rate가 줄어든 이유:**

```
① 악용: 낮은 Stable Rate로 빌린 뒤 시장 이자율 오르면 이득
② 복잡성: Variable + Stable 두 개 관리 → 코드/감사 비용 증가
③ 수요 부족: DeFi 사용자 대부분 단기 차입 → 변동금리 선호

Aave V3 현재: 대부분 자산에서 Stable Rate 비활성화
업계 전체: Variable Rate로 수렴하는 추세
고정금리 수요 → Notional, Pendle 같은 전문 프로토콜로 이동
```

---

## Scaled Balance 심화 — 왜 가스비를 절약하는가?

### "스케일링"이란?

```
Scaled Balance = 예치 시점의 index로 나눈 값 (정규화된 값)
              = 예치금 / 예치 시점의 liquidityIndex

예시:
  예치: 1,000 USDC, 이때 liquidityIndex = 1.02
  scaledBalance = 1,000 / 1.02 = 980.39

  나중에: liquidityIndex = 1.07
  실제 잔고 = 980.39 × 1.07 = 1,048.82 USDC (이자 포함)

핵심: scaledBalance는 한번 저장하면 안 바꿔도 됨
     index만 전역으로 업데이트하면 됨
```

### V1 vs V2 — 이자 반영 방식 비교

```
V1 (순진한 rebase 방식):
  이자 발생할 때마다 모든 사용자의 잔고를 업데이트해야 함

  사용자 1,000명이 예치한 상태에서 이자 발생:
  → user[0].balance = 새 값   ← SSTORE (스토리지 쓰기)
  → user[1].balance = 새 값   ← SSTORE
  → ...
  → user[999].balance = 새 값 ← SSTORE
  = 1,000번의 SSTORE 필요!

V2+ (scaled balance 방식):
  이자 발생할 때 전역 변수 1개만 업데이트

  사용자 1,000명이 예치한 상태에서 이자 발생:
  → liquidityIndex = 새 값    ← SSTORE 1번만!

  각 사용자의 잔고는?
  → balanceOf(user) 호출 시 계산: scaledBalance × liquidityIndex
  → 이건 읽기(SLOAD)만 하면 됨, 쓰기(SSTORE) 안 함
```

### EVM 옵코드 가스 비용

```
SSTORE (스토리지에 쓰기):
  - 0 → non-zero:  20,000 gas  (새 슬롯에 처음 쓰기)
  - non-zero → non-zero: 5,000 gas (기존 값 수정)

SLOAD (스토리지에서 읽기):
  - Cold (처음 읽기): 2,100 gas
  - Warm (같은 tx에서 재읽기): 100 gas

MUL (곱셈): 5 gas
DIV (나눗셈): 5 gas

비율:
  쓰기는 읽기보다 ~2.4배 비쌈
  쓰기는 계산보다 ~1,000배 비쌈!
```

### 왜 SSTORE가 비싼가? — EVM 코어 레벨

```
SLOAD (읽기):
  1. 메모리에서 Merkle Patricia Trie 탐색
  2. 해당 storage slot의 값을 읽어옴
  → 트리 탐색만 하면 됨

SSTORE (쓰기):
  1. 기존 값 읽기 (SLOAD와 같은 과정)
  2. 새 값을 storage slot에 쓰기
  3. ★ Merkle Patricia Trie 재계산 ★
     → 변경된 노드부터 루트까지 모든 해시를 다시 계산
     → 이게 진짜 비싼 이유!
  4. State root 업데이트
  5. 디스크에 영구 저장 (모든 노드가 이 데이터를 저장해야 함)

핵심: 쓰기는 "전세계 이더리움 노드의 디스크에 영구히 저장"되는 것
     → 네트워크 전체의 저장 비용을 가스비로 지불
     → 읽기는 그냥 내 노드에서 조회만 하면 됨
```

### 구체적 가스비 비교

```
시나리오: 사용자 1,000명, 이자 업데이트 1회

V1 (모든 사용자 잔고 업데이트):
  1,000 × SSTORE(5,000) = 5,000,000 gas
  + 오버헤드 ≈ 총 ~7,000,000 gas
  → 가스비 (~30 gwei, ETH $3,000): 약 $630 per update!

V2+ (전역 index만 업데이트):
  1 × SSTORE(5,000) = 5,000 gas
  + 약간의 계산 ≈ 총 ~30,000 gas
  → 가스비: 약 $2.70 per update

  절약: $630 → $2.70 = 99.6% 절약!

balanceOf() 호출 시 (V2+ 추가 비용):
  SLOAD(scaledBalance) + SLOAD(liquidityIndex) + MUL + DIV
  = 2,100 + 2,100 + 5 + 5 = 4,210 gas
  → view 함수이므로 외부 호출 시 가스비 0 (eth_call)
```

### 코드 레벨 비교

```solidity
// ===== V1: 순진한 rebase (가스 비쌈) =====
contract ATokenV1 {
    mapping(address => uint256) public balances;
    address[] public users;

    // 이자 발생할 때마다 호출 — O(N) SSTORE!
    function accrueInterest(uint256 rate) external {
        for (uint i = 0; i < users.length; i++) {
            balances[users[i]] = balances[users[i]] * rate / 1e18;
            // ↑ 매번 SSTORE × N명
        }
    }

    function balanceOf(address user) public view returns (uint256) {
        return balances[user];  // 그냥 읽기만
    }
}

// ===== V2+: Scaled Balance (가스 절약) =====
contract ATokenV2 {
    mapping(address => uint256) internal _scaledBalances;
    // liquidityIndex는 Pool 컨트랙트에 전역 1개만 저장

    function balanceOf(address user) public view returns (uint256) {
        return _scaledBalances[user] * pool.liquidityIndex() / 1e27;
        // ↑ SLOAD 2번 + MUL + DIV = ~4,210 gas
        // view 함수 → 외부 호출 시 가스비 0!
    }

    function scaledBalanceOf(address user) public view returns (uint256) {
        return _scaledBalances[user];  // 정규화된 원본 값
    }
}
```

```
핵심 인사이트:
  "계산을 읽기 시점으로 미룬다" = "쓰기를 없앤다"

  V1: 쓰기 시점에 모든 사용자 잔고 업데이트 (비쌈)
  V2: 읽기 시점에 곱셈 1번 (거의 공짜)

  이건 cToken의 exchangeRate와도 같은 원리:
  → cToken도 exchange_rate 전역 1개만 업데이트
  → 인출할 때 shares × exchangeRate로 계산
  → 결국 둘 다 "쓰기를 최소화하고 읽기에서 계산" 하는 전략
```

---

## 우리 프로젝트의 LToken

```
contracts/src/LToken.sol → Aave 스타일 (1:1 mint/burn)

  deposit: pool이 LToken.mint(user, amount) 호출 → 1:1 발행
  withdraw: pool이 LToken.burn(user, amount) 호출 → 1:1 소각

  단순화를 위해 rebase 없이 구현
  Simplified without rebase for learning purposes
  실제 Aave는 scaledBalance + liquidityIndex로 이자를 반영
```
