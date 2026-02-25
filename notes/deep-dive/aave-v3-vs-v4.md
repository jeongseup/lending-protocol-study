# Aave V3 vs V4 — 아키텍처 비교

## V3 아키텍처: Market-per-Pool (체인별 독립 풀)

```
V3 구조:

  Ethereum         Arbitrum          Polygon
┌──────────┐   ┌──────────┐    ┌──────────┐
│ Pool     │   │ Pool     │    │ Pool     │
│          │   │          │    │          │
│ ETH  $5B │   │ ETH $500M│    │ ETH $200M│
│ USDC $3B │   │ USDC $1B │    │ USDC $300M│
│ DAI  $1B │   │ DAI $200M│    │ DAI $50M │
└──────────┘   └──────────┘    └──────────┘
   독립적            독립적           독립적
   별도 유동성       별도 유동성      별도 유동성
```

V3의 특징:
- 각 체인에 **완전히 독립된 Pool**이 있음
- 유동성이 체인별로 분산 (fragmented)
- 새 기능 추가 = 새 Pool 배포 + 유동성 이전 필요
- Portal로 크로스체인 지원하지만, 실제 유동성 통합은 아님

V3의 핵심 기능들 (우리가 이미 구현/학습한 것):
- **E-Mode**: 상관 자산 높은 LTV (예: stETH/ETH)
- **Isolation Mode**: 신규 자산 격리 등록
- **Supply/Borrow Caps**: 자산별 한도 설정
- **변동 금리**: utilization 기반 2-slope 이자율 모델

## V4 아키텍처: Hub & Spoke (통합 유동성 허브)

```
V4 구조:

                    ┌───────────────────┐
                    │   LIQUIDITY HUB   │
                    │                   │
                    │  통합 유동성 관리    │
                    │  ETH: $5.7B 총합   │
                    │  USDC: $4.3B 총합  │
                    │  크레딧 라인 발행    │
                    └─────┬─────┬───────┘
                          │     │
              ┌───────────┤     ├───────────┐
              │           │     │           │
        ┌─────▼────┐ ┌───▼─────▼──┐ ┌─────▼────┐
        │ Spoke A  │ │  Spoke B   │ │ Spoke C  │
        │ Main     │ │ Stablecoin │ │ RWA      │
        │ Market   │ │ Market     │ │ Market   │
        │          │ │            │ │          │
        │ 일반 대출 │ │ 스테이블    │ │ 실물 자산  │
        │ ETH/USDC │ │ USDC/DAI   │ │ T-Bill등  │
        └──────────┘ └────────────┘ └──────────┘
          자체 리스크     자체 리스크     자체 리스크
          자체 오라클     자체 오라클     자체 오라클
          자체 청산 설정   자체 청산 설정   자체 청산 설정
```

## Hub & Spoke가 렌딩에서 해결하는 문제

### 문제 1: 유동성 분산 (Liquidity Fragmentation)

```
V3의 문제:

  Pool A (일반 시장):     USDC 유동성 $3B
  Pool B (RWA 시장):      USDC 유동성 $500M  ← 따로 노는 유동성
  Pool C (스테이블 시장):  USDC 유동성 $1B   ← 따로 노는 유동성

  → 총 $4.5B인데, 각 풀은 자기 유동성만 사용 가능
  → Pool B에서 대출 수요 급증해도 Pool A의 유동성을 못 씀

V4의 해결:

  Hub: USDC 통합 유동성 $4.5B
  → Spoke A가 $3B credit line으로 접근
  → Spoke B가 $500M credit line으로 접근
  → Spoke C가 $1B credit line으로 접근

  → Spoke B에서 대출 수요 급증?
  → Hub가 credit line 범위 내에서 유동성 재분배 가능
  → 전체 $4.5B가 효율적으로 활용됨
```

네트워크의 Hub & Spoke와 비교:

```
네트워크:  Hub(라우터)가 트래픽을 효율적으로 분배
렌딩:      Hub가 유동성(=자금)을 효율적으로 분배

네트워크:  각 Spoke(엔드포인트)는 Hub를 통해 통신
렌딩:      각 Spoke(시장)는 Hub를 통해 유동성 접근

네트워크:  Hub에서 중앙 관리 (라우팅 테이블, ACL)
렌딩:      Hub에서 중앙 관리 (크레딧 라인, 긴급 정지)
```

### 문제 2: 새 기능 추가 시 유동성 이전

```
V3: 새 시장(예: RWA) 추가하려면?
  1. 새 Pool 컨트랙트 배포
  2. 유동성 공급자가 기존 풀에서 출금
  3. 새 풀에 재예치
  4. 과도기 동안 유동성 부족 → 이자율 급등
  5. 마이그레이션에 수 주~수 개월 소요

V4: 새 시장 추가하려면?
  1. 새 Spoke 컨트랙트 배포
  2. Hub에서 credit line 설정
  3. 끝. 유동성은 이미 Hub에 있음.
  → 유동성 이전 불필요!
```

### 문제 3: 리스크 격리

```
V3의 Isolation Mode:
  같은 Pool 안에서 특정 자산만 격리
  → 하지만 Pool 전체가 영향 받을 수 있음

V4의 Spoke 격리:
  위험한 자산 = 별도 Spoke에 배치
  → Spoke C(RWA)에서 문제 발생해도
  → Spoke A(메인 시장)는 전혀 영향 없음
  → Hub의 credit line이 손실을 해당 Spoke로 제한

비유:
  V3 = 아파트 한 건물에 방화벽 설치
  V4 = 아예 별도 건물로 분리 (하지만 수도/전기는 공유)
```

## V4의 새로운 청산 메커니즘

V4는 우리가 방금 공부한 Dutch Auction과 유사한 메커니즘을 도입했다:

```
V3 청산: 고정 보너스 (예: 5%)
  → 항상 같은 보너스 → MEV 경쟁 → 비효율

V4 청산: Variable Liquidation Bonus
  → HF에 따라 보너스가 변동
  → HF = 0.95 (약간 위험): 보너스 낮음 (2%)
  → HF = 0.50 (매우 위험): 보너스 높음 (10%)
  → Dutch Auction과 같은 원리: 시장이 적정 보너스를 결정

V4 추가 기능:
  - Target Health Factor: 청산 후 목표 HF로 복원 (과도 청산 방지)
  - Dust Prevention: $1,000 이하 잔여 포지션은 전액 청산
  - User Risk Premium: 담보 품질에 따라 개인별 금리 차등
```

## V3 vs V4 비교표

```
                        V3                          V4
──────────────────────────────────────────────────────────────
아키텍처         Market-per-Pool              Hub & Spoke
유동성           체인/풀별 분산               Hub에서 통합 관리
새 시장 추가     새 풀 배포 + 이전            Spoke 추가만 (이전 불필요)
리스크 격리      Isolation Mode (풀 내)       Spoke 단위 (물리적 분리)
청산 보너스      고정 (자산별)                변동 (HF 기반, Dutch Auction식)
크로스체인       Portal (제한적)              Hub가 중앙 조정
이자율           풀별 독립 계산               User Risk Premium 추가
업그레이드       풀 전체 마이그레이션          Spoke 단위 교체
──────────────────────────────────────────────────────────────
```

## Hub & Spoke의 트레이드오프

```
장점:
  ✅ 유동성 효율성 극대화 (분산 → 통합)
  ✅ 모듈형 확장 (Spoke 추가만으로 새 시장)
  ✅ 리스크 격리 강화 (Spoke 간 방화벽)
  ✅ 업그레이드 유연성 (전체 이전 불필요)

단점/리스크:
  ⚠️ Hub = 단일 장애점 (Single Point of Failure)
     Hub 컨트랙트 취약점 → 전체 프로토콜 위험
  ⚠️ 복잡도 증가 (Hub-Spoke 간 통신, credit line 관리)
  ⚠️ 거버넌스 복잡화 (Hub 파라미터 + 각 Spoke 파라미터)
  ⚠️ 크로스체인 Hub의 경우 메시지 지연/실패 위험

네트워크 Hub & Spoke와 같은 근본적 트레이드오프:
  중앙화된 효율성 vs 분산화된 안정성
```

## 우리 프로토콜과의 연결

```
우리 LendingPool.sol = V3 스타일 (단일 Pool)

V4 스타일로 발전시키려면:
  1. LendingPool.sol → LiquidityHub.sol (유동성 통합 관리)
  2. Spoke 컨트랙트 추가 (시장별 독립 로직)
  3. credit line 메커니즘 (Hub → Spoke 유동성 할당)
  4. Variable Liquidation Bonus (HF 기반 동적 보너스)

하지만 현재 학습 단계에서는:
  V3 패턴을 충분히 이해하는 것이 우선
  V4는 "V3의 한계를 어떻게 해결했는가" 관점으로 참고
```
