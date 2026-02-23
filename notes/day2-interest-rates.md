# Day 2: 이자율 모델 + Solidity 심화
# Day 2: Interest Rate Models + Solidity Deep Dive

## Jump Rate Model — 점프 이자율 모델

### 작동 원리 / How it Works
```
이자율
 ^
 |         ___/ (jumpMultiplier — 급격한 기울기)
 |        /
 |       / ← kink (80%)
 |      /
 |     / (multiplier — 완만한 기울기)
 |    /
 |___/ baseRate (2%)
 +---+---+---+---+---→ 사용률 (Utilization)
 0%  20% 40% 60% 80% 100%
```

### 핵심 파라미터 / Key Parameters
- `baseRate`: 기본 이자율 (예: 2%) / Base rate (e.g., 2%)
- `multiplier`: kink 이하 기울기 / Slope below kink
- `jumpMultiplier`: kink 이상 급격한 기울기 / Steep slope above kink
- `kink`: 최적 사용률 (보통 80%) / Optimal utilization (typically 80%)

### 구현 코드 / Implementation
- `contracts/src/JumpRateModel.sol` 참조 / See JumpRateModel.sol
- 테스트: `contracts/test/JumpRateModel.t.sol` / Tests: JumpRateModel.t.sol

## Aave V3 아키텍처 / Aave V3 Architecture

### cToken vs aToken 모델 비교 / cToken vs aToken Model Comparison
| 특성 | cToken (Compound) | aToken (Aave) |
|------|-------------------|---------------|
| 잔액 | 고정 | 리베이스 (자동 증가) |
| 이자 | 환율 증가로 반영 | 잔액 직접 증가 |
| Balance | Fixed | Rebases (auto-increases) |
| Interest | Reflected via exchange rate | Balance directly increases |

## 할 일 / TODO
- [ ] 가이드 섹션 5 읽기 / Read guide Section 5
- [ ] Alberto Cuesta 아티클 읽기 / Read Alberto Cuesta article
- [ ] JumpRateModel 구현 및 테스트 / Implement and test JumpRateModel
- [ ] Aave V3 코드 분석 / Analyze Aave V3 code
