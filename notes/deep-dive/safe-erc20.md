# SafeERC20 vs ERC20 — `using SafeERC20 for IERC20` 의 의미

> LendingPool.sol:18의 `using SafeERC20 for IERC20;`가 왜 렌딩 프로토콜에 필수인가

---

## 문제: ERC20 표준의 허점

```
ERC20 표준 (EIP-20)은 transfer/approve 함수의 반환값 처리가 모호하다:

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
}

문제: "returns (bool)"인데, 실제로 bool을 리턴하지 않는 토큰이 존재한다!
```

### 실제 문제 토큰 사례

```
USDT (Tether) — DeFi에서 가장 많이 사용되는 스테이블코인:

// USDT의 실제 transfer 함수 (이더스캔 verified)
function transfer(address _to, uint _value) public {
    // ... 로직 ...
    // ❌ 리턴값이 없음! (returns 없음)
}

// ERC20 표준 대로라면:
function transfer(address _to, uint _value) public returns (bool) {
    // ... 로직 ...
    return true;  // ✅ bool 리턴
}

BNB, OMG, KNC 등도 동일한 문제 — 리턴값이 없거나 다른 형태
```

### 리턴값 없으면 무슨 일이 발생하는가?

```solidity
// 위험한 코드 — SafeERC20 없이 직접 호출
function deposit(address token, uint256 amount) external {
    // USDT로 호출하면?
    IERC20(token).transfer(msg.sender, amount);
    // ↑ Solidity가 bool 반환을 기대하는데
    //   USDT는 아무것도 리턴하지 않음
    //   → Solidity 0.8+: REVERT (반환 데이터 디코딩 실패)
    //   → 사용자는 USDT를 예치할 수 없음!
}

// 또 다른 위험 — 실패해도 모르는 경우
function withdraw(address token, uint256 amount) external {
    bool success = IERC20(token).transfer(msg.sender, amount);
    // 일부 토큰은 실패 시 false를 리턴 (revert 안 함)
    // success를 체크하지 않으면?
    // → 전송 실패했는데 상태는 이미 변경됨 → 자금 손실!
}
```

---

## 해결: SafeERC20 라이브러리

```solidity
// OpenZeppelin의 SafeERC20 — 핵심 아이디어
library SafeERC20 {
    function safeTransfer(IERC20 token, address to, uint256 value) internal {
        // 저수준 호출로 리턴값 유무에 관계없이 처리
        bytes memory returndata = address(token).functionCall(
            abi.encodeCall(token.transfer, (to, value))
        );

        // 리턴 데이터가 있으면 → bool 체크
        // 리턴 데이터가 없으면 → 리턴 없는 토큰이므로 OK (revert 안 했으면 성공)
        if (returndata.length != 0) {
            require(abi.decode(returndata, (bool)), "SafeERC20: operation failed");
        }
    }
}
```

### 🔬 EVM Opcode 레벨 상세 분석 — safeTransfer 내부 동작

위 코드가 실제로 EVM에서 어떻게 실행되는지, 단계별로 분해해보자.

#### Step 1: `abi.encodeCall` — 호출 데이터(calldata) 생성

```solidity
abi.encodeCall(token.transfer, (to, value))
```

이 코드는 ERC20의 `transfer(address,uint256)` 함수를 호출하기 위한 raw bytes를 만든다.

```
결과 바이트 구조 (총 68 bytes):
┌──────────────────────────────────────────────────────────────────────┐
│ [0x00 ~ 0x03] function selector (4 bytes)                          │
│   = keccak256("transfer(address,uint256)") 의 앞 4바이트           │
│   = 0xa9059cbb                                                      │
├──────────────────────────────────────────────────────────────────────┤
│ [0x04 ~ 0x23] 첫 번째 인자: to (address, 32 bytes로 패딩)          │
│   = 0x000000000000000000000000Abcd...1234                           │
├──────────────────────────────────────────────────────────────────────┤
│ [0x24 ~ 0x43] 두 번째 인자: value (uint256, 32 bytes)              │
│   = 0x0000000000000000000000000000000000000000000000000DE0B6B3A7640000│
│     (예: 1 ether = 10^18)                                           │
└──────────────────────────────────────────────────────────────────────┘

이 68 bytes가 EVM 메모리에 저장됨 → 이후 CALL opcode의 입력으로 사용
```

> **Q: 모든 인자가 32 bytes로 패딩되는데, 어떻게 타입을 검증하는가?**
>
> 핵심: 타입 검증은 **컴파일 타임**에 일어난다. 런타임(EVM)에서는 이미 32 bytes 패딩된
> raw bytes만 존재하고, EVM은 calldata의 타입을 알 방도가 없다.
> `abi.encodeCall`의 "타입 안전"은 **Solidity 컴파일러**가 제공하는 것이다.

```solidity
// ✅ abi.encodeCall — 컴파일러가 token.transfer의 시그니처를 보고 타입 체크
abi.encodeCall(token.transfer, (to, value))
//              ↑ 컴파일러: "transfer(address, uint256)이니까
//                           to는 address, value는 uint256이어야 해"

// 실수로 인자 순서를 뒤집으면?
abi.encodeCall(token.transfer, (value, to))
// ❌ 컴파일 에러! "uint256 is not implicitly convertible to address"

// ❌ abi.encodeWithSelector — 컴파일러가 타입을 검증하지 않음
abi.encodeWithSelector(IERC20.transfer.selector, value, to)
// ↑ 컴파일 통과됨! 인자 순서가 뒤집혔지만 그냥 bytes를 이어붙이기만 함
// → 런타임에 잘못된 address로 토큰이 전송되는 심각한 버그 발생
```

```
정리: 컴파일 타임 vs 런타임
┌────────────────────────────┬──────────────────────────────────┐
│ 컴파일 타임 (Solidity)      │ 런타임 (EVM)                     │
├────────────────────────────┼──────────────────────────────────┤
│ abi.encodeCall:            │ 둘 다 동일한 바이트코드 생성!      │
│  → 함수 시그니처 참조       │ 0xa9059cbb + arg1(32B) + arg2(32B)│
│  → 인자 타입/개수 검증      │                                  │
│  → 틀리면 컴파일 에러       │ EVM은 타입을 모름                 │
├────────────────────────────┤ 그냥 bytes 덩어리로 취급           │
│ abi.encodeWithSelector:    │                                  │
│  → selector만 체크          │                                  │
│  → 인자는 any로 취급        │                                  │
│  → 타입 틀려도 컴파일 통과  │                                  │
└────────────────────────────┴──────────────────────────────────┘
→ abi.encodeCall은 "컴파일러의 타입시스템을 활용한 안전장치"
→ 런타임에서 추가 가스 비용 없음 (생성되는 바이트코드는 동일)
```

#### Step 2: `address(token).functionCall(...)` — 저수준 CALL 실행

`functionCall`은 OpenZeppelin `Address` 라이브러리의 함수로, 내부적으로 이렇게 동작한다:

```solidity
// Address.functionCall 의 핵심 (단순화)
function functionCall(address target, bytes memory data) internal returns (bytes memory) {
    (bool success, bytes memory returndata) = target.call(data);
    //                                        ↑ 여기가 EVM CALL opcode
    if (!success) {
        // revert 시 에러 메시지 전파
        _revert(returndata);
    }
    return returndata;
}
```

이 `target.call(data)`가 **EVM CALL opcode**로 컴파일된다:

```
EVM CALL Opcode (0xF1) — 스택에 올라가는 7개 인자:

  PUSH gas          ← 전달할 가스량 (EVM이 자동 계산)
  PUSH addr         ← 토큰 컨트랙트 주소 (예: USDT 컨트랙트)
  PUSH value        ← 전송할 ETH (여기서는 0)
  PUSH argsOffset   ← 메모리에서 calldata 시작 위치
  PUSH argsLength   ← calldata 길이 (68 bytes)
  PUSH retOffset    ← 반환 데이터를 저장할 메모리 위치
  PUSH retLength    ← 반환 데이터 예상 길이
  CALL              ← 실행!

  → 스택에 success (0 또는 1)가 push됨
```

**CALL 실행 시 일어나는 일:**

1. EVM이 토큰 컨트랙트의 코드를 로드
2. 새로운 execution context (call frame) 생성
3. calldata (68 bytes)를 넘기면서 토큰의 `transfer` 함수 실행
4. 토큰 내부에서 잔액 체크, 이벤트 발생, 상태 변경 등 수행
5. 실행이 끝나면 **return data**를 caller에게 돌려줌

#### Step 3: Return Data 처리 — RETURNDATASIZE & RETURNDATACOPY

CALL 이후, **반환 데이터를 읽는 것이 핵심**이다.
EVM은 Byzantium 하드포크(EIP-211)부터 두 개의 opcode를 제공한다:

```
RETURNDATASIZE (0x3D)
  → 마지막 외부 호출의 반환 데이터 크기를 스택에 push
  → 아무 인자도 필요 없음

RETURNDATACOPY (0x3E)
  → 반환 데이터를 메모리로 복사
  → 스택 인자: destOffset, offset, length
```

**Solidity가 생성하는 실제 어셈블리 흐름:**

```
CALL              ; 토큰의 transfer 호출
                  ; → stack: [success]

RETURNDATASIZE    ; 반환 데이터 크기 확인
                  ; → stack: [success, returndata_size]

; returndata_size 만큼 메모리 할당 후 복사
RETURNDATACOPY    ; 반환 데이터를 메모리로 복사

; 이제 Solidity의 bytes memory returndata에 반환 데이터가 들어있음
```

#### Step 4: SafeERC20의 분기 처리 — 핵심 로직

```solidity
if (returndata.length != 0) {
    require(abi.decode(returndata, (bool)), "SafeERC20: operation failed");
}
```

이 부분이 **왜 천재적인지** opcode 레벨에서 보면:

```
Case A: 표준 ERC20 토큰 (예: DAI) — bool true 리턴
─────────────────────────────────────────────────────
  CALL 실행 → success = 1
  RETURNDATASIZE → 32 (bytes)
  반환 데이터 = 0x0000...0001 (bool true를 ABI 인코딩한 32 bytes)

  returndata.length = 32 → 0이 아님 → if 진입
  abi.decode(returndata, (bool)) → true → require 통과 ✅

Case B: USDT 같은 비표준 토큰 — 리턴값 없음
─────────────────────────────────────────────────────
  CALL 실행 → success = 1 (revert 안 했으므로)
  RETURNDATASIZE → 0 (bytes) — 아무것도 리턴하지 않았음!

  returndata.length = 0 → if 진입 안 함 → 그냥 통과 ✅
  (revert 안 했으면 성공으로 간주)

Case C: 전송 실패하는 토큰 — false 리턴
─────────────────────────────────────────────────────
  CALL 실행 → success = 1 (revert 대신 false를 리턴하는 토큰)
  RETURNDATASIZE → 32
  반환 데이터 = 0x0000...0000 (bool false)

  returndata.length = 32 → if 진입
  abi.decode(returndata, (bool)) → false → require 실패 → REVERT ✅

Case D: 호출 자체가 실패 — revert
─────────────────────────────────────────────────────
  CALL 실행 → success = 0 (토큰 내부에서 revert)
  → functionCall에서 이미 revert 처리됨 (safeTransfer까지 안 옴) ✅
```

#### 전체 실행 흐름 요약 (Opcode 순서)

```
safeTransfer(token, to, 100) 호출 시:

1. MSTORE    — "0xa9059cbb" + to + value를 메모리에 저장 (calldata 준비)
2. CALL      — 토큰 컨트랙트에 transfer(to, value) 실행
     ↳ gas, addr, 0, argsOffset, 68, retOffset, retLength
3. ISZERO    — success == 0이면 revert (functionCall 내부)
4. RETURNDATASIZE — 반환 데이터 크기 확인
5. RETURNDATACOPY — 반환 데이터를 메모리로 복사
6. MLOAD     — returndata.length 읽기
7. ISZERO    — length == 0이면 그냥 통과 (USDT Case)
8. CALLDATALOAD / MLOAD — returndata에서 bool 값 추출
9. ISZERO    — bool == false이면 REVERT

→ 이 모든 과정이 ~3000 gas 이내에 처리됨
```

> **왜 일반적인 Solidity 호출이 아닌 저수준(low-level) 호출을 쓰는가?**
>
> 일반 Solidity 호출 `IERC20(token).transfer(to, value)`는 컴파일러가 자동으로
> "반환값이 정확히 32 bytes (bool)여야 한다"는 체크를 삽입한다.
> USDT처럼 0 bytes를 리턴하면 이 체크에서 **무조건 revert**된다.
> 저수준 `call`은 이 자동 체크를 우회하고, 직접 `RETURNDATASIZE`로
> 반환 데이터 유무를 판단할 수 있게 해준다.

### SafeERC20이 해결하는 3가지 문제

```
문제 1: 리턴값 없는 토큰 (USDT, BNB 등)
  IERC20.transfer()     → ❌ revert (리턴 데이터 없어서 디코딩 실패)
  SafeERC20.safeTransfer → ✅ 정상 동작 (리턴 없으면 그냥 성공으로 처리)

문제 2: 실패 시 false 리턴하는 토큰
  IERC20.transfer()     → false 리턴 (revert 안 함) → 체크 안 하면 자금 손실
  SafeERC20.safeTransfer → ✅ false면 자동으로 revert

문제 3: approve race condition
  IERC20.approve(spender, newAmount)
    → 기존 allowance가 0이 아니면 프론트러닝 위험
  SafeERC20.forceApprove(spender, amount)
    → 먼저 0으로 설정 후 새 값 설정 (2-step)
```

---

## `using SafeERC20 for IERC20` 문법 설명

```solidity
contract LendingPool {
    using SafeERC20 for IERC20;  // ← 이 한 줄의 의미

    // 효과: IERC20 타입의 모든 변수에서
    // SafeERC20의 함수를 "메서드처럼" 호출 가능

    function deposit(address asset, uint256 amount) external {
        // using 없이:
        SafeERC20.safeTransferFrom(IERC20(asset), msg.sender, address(this), amount);

        // using으로 간결하게:
        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
        //             ↑ IERC20에는 safeTransferFrom이 없다!
        //               하지만 using...for 덕분에 SafeERC20의 함수가 붙음
    }
}
```

### using...for 동작 원리

```solidity
// using A for B;
// = "A 라이브러리의 함수들을 B 타입의 메서드로 사용하겠다"

// SafeERC20 라이브러리 정의:
library SafeERC20 {
    function safeTransfer(IERC20 token, address to, uint256 value) internal { ... }
    //                    ↑ 첫 번째 매개변수가 "this"가 됨
}

// using SafeERC20 for IERC20; 적용 후:
IERC20(asset).safeTransfer(to, value);
// → SafeERC20.safeTransfer(IERC20(asset), to, value); 로 변환됨
//                          ↑ 자동으로 전달

// Rust의 trait impl이나 Go의 method receiver와 유사한 개념
// Solidity만의 "extension method" 패턴
```

---

## LendingPool에서의 실제 사용 매핑

```
LendingPool.sol에서 SafeERC20이 사용되는 6곳:

deposit():
  L233: IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
  → 사용자 → 풀로 자산 이동 (예치)

withdraw():
  L284: IERC20(asset).safeTransfer(msg.sender, amount);
  → 풀 → 사용자로 자산 반환 (인출)

borrow():
  L321: IERC20(asset).safeTransfer(msg.sender, amount);
  → 풀 → 차입자에게 자산 전송 (대출)

repay():
  L345: IERC20(asset).safeTransferFrom(msg.sender, address(this), repayAmount);
  → 차입자 → 풀로 자산 반환 (상환)

liquidate():
  L396: IERC20(debtAsset).safeTransferFrom(msg.sender, address(this), debtToCover);
  → 청산자 → 풀로 부채 자산 상환

  L426: IERC20(collateralAsset).safeTransfer(msg.sender, collateralToSeize);
  → 풀 → 청산자에게 담보 + 보너스 전송

패턴 정리:
  safeTransferFrom = 외부 → 풀 (사용자가 보내는 경우)
  safeTransfer     = 풀 → 외부 (풀이 보내는 경우)
```

---

## ERC20 vs SafeERC20 비교표

```
┌──────────────────┬─────────────────────────┬─────────────────────────┐
│                  │ ERC20 (직접 호출)        │ SafeERC20               │
├──────────────────┼─────────────────────────┼─────────────────────────┤
│ USDT 지원         │ ❌ revert               │ ✅ 정상 동작             │
│ USDT support     │ Fails (no return data)  │ Works                   │
├──────────────────┼─────────────────────────┼─────────────────────────┤
│ 실패 감지         │ ❌ false 무시 가능       │ ✅ 자동 revert           │
│ Failure detect   │ Can ignore false        │ Auto-reverts            │
├──────────────────┼─────────────────────────┼─────────────────────────┤
│ approve 안전성    │ ❌ 프론트러닝 위험       │ ✅ forceApprove          │
│ approve safety   │ Front-run risk          │ 2-step (0 then set)     │
├──────────────────┼─────────────────────────┼─────────────────────────┤
│ 가스 비용         │ 약간 적음               │ 약간 많음 (~200 gas)     │
│ Gas cost         │ Slightly less           │ Slightly more           │
├──────────────────┼─────────────────────────┼─────────────────────────┤
│ 사용 프로토콜     │ 없음 (위험)              │ Aave, Compound, 거의 전부│
│ Used by          │ None (dangerous)        │ All major protocols     │
├──────────────────┼─────────────────────────┼─────────────────────────┤
│ 렌딩에서 필수?    │ -                       │ ✅ 절대 필수             │
│ Required?        │                         │ Absolutely required     │
└──────────────────┴─────────────────────────┴─────────────────────────┘

결론:
  렌딩 프로토콜은 USDT, USDC 등 다양한 ERC20 토큰을 다뤄야 한다.
  SafeERC20 없이는 USDT 예치/인출이 불가능하다.
  → 렌딩 프로토콜에서 SafeERC20은 "선택"이 아니라 "필수"
```

---

## 왜 렌딩 프로토콜 맨 위에 선언하는가?

```
contract LendingPool {
    using SafeERC20 for IERC20;  // ← Line 18

이유:
  1. LendingPool은 모든 함수에서 ERC20 토큰을 전송한다
     deposit, withdraw, borrow, repay, liquidate — 전부 토큰 이동
  2. 어떤 ERC20 토큰이 등록될지 모른다
     USDT(리턴값 없음)도 올 수 있고, 표준 토큰도 올 수 있다
  3. 컨트랙트 전체에서 사용하므로 최상단에 선언
     → 모든 함수에서 .safeTransfer() / .safeTransferFrom() 사용 가능

실제 Aave V3도 동일:
  // aave-v3-origin/src/contracts/protocol/pool/Pool.sol
  using SafeERC20 for IERC20;

Compound V2는 다른 접근:
  // 직접 저수준 호출을 구현 (SafeERC20 등장 전이라서)
  function doTransferIn(address from, uint amount) internal returns (uint) {
      // ... assembly level call ...
  }
```

---

## Solidity `using...for` 패턴 추가 예시

```solidity
// 패턴 1: 라이브러리 for 타입 (가장 일반적)
using SafeERC20 for IERC20;        // ERC20 안전 호출
using SafeMath for uint256;         // 오버플로 방지 (0.8 이전)
using EnumerableSet for EnumerableSet.AddressSet;  // 집합 자료구조

// 패턴 2: 글로벌 using (Solidity 0.8.13+)
using { add, mul } for uint256 global;

// 패턴 3: Aave에서의 실제 사용
using ReserveLogic for DataTypes.ReserveData;
// → ReserveData 구조체에 .updateState(), .updateInterestRates() 등 "메서드" 추가
// → OOP의 메서드처럼 사용: reserve.updateState();

// 패턴 4: 렌딩 프로토콜에서 자주 보는 조합
using SafeERC20 for IERC20;           // 토큰 안전 전송
using WadRayMath for uint256;          // 고정소수점 연산 (Aave)
using PercentageMath for uint256;      // 퍼센트 계산 (Aave)
using ReserveConfiguration for DataTypes.ReserveConfigurationMap;  // 비트맵 접근
```
