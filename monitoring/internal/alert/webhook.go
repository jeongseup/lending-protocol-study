// Package alert는 렌딩 프로토콜 모니터링 알림을 전송하는 기능을 제공합니다.
// Package alert provides alerting functionality for lending protocol monitoring.
package alert

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"math/big"
	"net/http"
	"time"
)

// AlertLevel은 알림의 심각도를 나타냅니다.
// AlertLevel represents the severity of an alert.
type AlertLevel string

const (
	// AlertInfo는 정보성 알림입니다.
	// AlertInfo is an informational alert.
	AlertInfo AlertLevel = "INFO"

	// AlertWarning은 경고 알림입니다 (예: HF < 1.2).
	// AlertWarning is a warning alert (e.g., HF < 1.2).
	AlertWarning AlertLevel = "WARNING"

	// AlertCritical은 긴급 알림입니다 (예: HF < 1.0, 오라클 장애).
	// AlertCritical is a critical alert (e.g., HF < 1.0, oracle failure).
	AlertCritical AlertLevel = "CRITICAL"
)

// Alert는 모니터링 알림 메시지입니다.
// Alert represents a monitoring alert message.
type Alert struct {
	// Level은 알림 심각도입니다.
	// Level is the alert severity.
	Level AlertLevel `json:"level"`

	// Title은 알림 제목입니다.
	// Title is the alert title.
	Title string `json:"title"`

	// Message는 알림 본문입니다.
	// Message is the alert body.
	Message string `json:"message"`

	// Timestamp는 알림 발생 시간입니다.
	// Timestamp is when the alert occurred.
	Timestamp time.Time `json:"timestamp"`

	// Metadata는 추가 컨텍스트 정보입니다.
	// Metadata is additional context information.
	Metadata map[string]string `json:"metadata,omitempty"`
}

// WebhookAlerter는 웹훅을 통해 알림을 전송합니다.
// WebhookAlerter sends alerts via webhook.
type WebhookAlerter struct {
	webhookURL string
	client     *http.Client
	logger     *slog.Logger
}

// NewWebhookAlerter는 새로운 WebhookAlerter를 생성합니다.
// NewWebhookAlerter creates a new WebhookAlerter.
func NewWebhookAlerter(webhookURL string, logger *slog.Logger) *WebhookAlerter {
	return &WebhookAlerter{
		webhookURL: webhookURL,
		client: &http.Client{
			Timeout: 10 * time.Second,
		},
		logger: logger,
	}
}

// SendAlert는 알림을 웹훅으로 전송합니다.
// SendAlert sends an alert via webhook.
func (w *WebhookAlerter) SendAlert(ctx context.Context, alert Alert) error {
	payload, err := json.Marshal(alert)
	if err != nil {
		return fmt.Errorf("알림 직렬화 실패 / failed to marshal alert: %w", err)
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, w.webhookURL, bytes.NewReader(payload))
	if err != nil {
		return fmt.Errorf("요청 생성 실패 / failed to create request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")

	resp, err := w.client.Do(req)
	if err != nil {
		return fmt.Errorf("웹훅 전송 실패 / failed to send webhook: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode >= 300 {
		return fmt.Errorf("웹훅 응답 오류: %d / webhook response error: %d", resp.StatusCode, resp.StatusCode)
	}

	w.logger.Info("알림 전송 완료 / Alert sent",
		"level", alert.Level,
		"title", alert.Title,
	)
	return nil
}

// AlertOnLowHealthFactor는 헬스팩터가 기준 이하일 때 알림을 전송합니다.
// AlertOnLowHealthFactor sends an alert when health factor is below threshold.
//
// 알림 기준 / Alert thresholds:
// - HF < 1.2 → WARNING (곧 청산 가능 / may become liquidatable soon)
// - HF < 1.0 → CRITICAL (즉시 청산 가능 / immediately liquidatable)
func (w *WebhookAlerter) AlertOnLowHealthFactor(ctx context.Context, user string, healthFactor *big.Float) error {
	one := new(big.Float).SetFloat64(1.0)
	warningThreshold := new(big.Float).SetFloat64(1.2)

	var level AlertLevel
	if healthFactor.Cmp(one) < 0 {
		level = AlertCritical
	} else if healthFactor.Cmp(warningThreshold) < 0 {
		level = AlertWarning
	} else {
		return nil // 건전한 포지션 / healthy position
	}

	alert := Alert{
		Level:     level,
		Title:     "낮은 헬스팩터 감지 / Low Health Factor Detected",
		Message:   fmt.Sprintf("사용자 %s의 헬스팩터: %s / User %s health factor: %s", user, healthFactor.Text('f', 4), user, healthFactor.Text('f', 4)),
		Timestamp: time.Now(),
		Metadata: map[string]string{
			"user":          user,
			"health_factor": healthFactor.Text('f', 6),
		},
	}

	return w.SendAlert(ctx, alert)
}

// AlertOnOracleStaleness는 오라클 지연을 감지했을 때 알림을 전송합니다.
// AlertOnOracleStaleness sends an alert when oracle staleness is detected.
func (w *WebhookAlerter) AlertOnOracleStaleness(ctx context.Context, feed string, staleness time.Duration, maxStaleness time.Duration) error {
	if staleness < maxStaleness {
		return nil
	}

	level := AlertWarning
	if staleness > 2*maxStaleness {
		level = AlertCritical
	}

	alert := Alert{
		Level:     level,
		Title:     "오라클 지연 감지 / Oracle Staleness Detected",
		Message:   fmt.Sprintf("피드 %s 지연: %v (최대 허용: %v) / Feed %s stale: %v (max: %v)", feed, staleness, maxStaleness, feed, staleness, maxStaleness),
		Timestamp: time.Now(),
		Metadata: map[string]string{
			"feed":           feed,
			"staleness":      staleness.String(),
			"max_staleness":  maxStaleness.String(),
		},
	}

	return w.SendAlert(ctx, alert)
}

// AlertOnHighUtilization은 사용률이 기준 이상일 때 알림을 전송합니다.
// AlertOnHighUtilization sends an alert when utilization exceeds threshold.
func (w *WebhookAlerter) AlertOnHighUtilization(ctx context.Context, asset string, utilization float64) error {
	if utilization < 0.9 {
		return nil // 90% 미만이면 정상 / normal if below 90%
	}

	level := AlertWarning
	if utilization > 0.95 {
		level = AlertCritical
	}

	alert := Alert{
		Level:     level,
		Title:     "높은 사용률 감지 / High Utilization Detected",
		Message:   fmt.Sprintf("자산 %s 사용률: %.2f%% / Asset %s utilization: %.2f%%", asset, utilization*100, asset, utilization*100),
		Timestamp: time.Now(),
		Metadata: map[string]string{
			"asset":       asset,
			"utilization": fmt.Sprintf("%.4f", utilization),
		},
	}

	return w.SendAlert(ctx, alert)
}
