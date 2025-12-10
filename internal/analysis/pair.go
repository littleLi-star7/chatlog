package analysis

import (
	"sort"
	"strings"
	"time"
	"unicode"

	"github.com/sjzar/chatlog/internal/model"
)

// ComputePairStats calculates statistics for the supplied messages.
func ComputePairStats(talker string, messages []*model.Message, start, end time.Time) *PairStats {
	stats := &PairStats{
		Talker:       talker,
		TimeStart:    start,
		TimeEnd:      end,
		Participants: make(map[string]*Side),
		Overview: &Overview{
			ParticipantShare: make(map[string]float64),
		},
		Activity: &Activity{
			Hourly: make(map[int]int),
			Weekly: make(map[time.Weekday]int),
		},
		Response: &ResponseInsights{
			AverageSeconds: make(map[string]float64),
			MedianSeconds:  make(map[string]float64),
			MinSeconds:     make(map[string]float64),
			MaxSeconds:     make(map[string]float64),
		},
		Content: &ContentBreakdown{
			MediaCounts: make(map[string]int),
		},
	}

	if len(messages) == 0 {
		return stats
	}

	// 先按时间排序，保证遍历顺序正确。
	sort.Slice(messages, func(i, j int) bool {
		return messages[i].Time.Before(messages[j].Time)
	})

	startTime := messages[0].Time
	endTime := messages[len(messages)-1].Time
	stats.Overview.FirstMessageAt = startTime
	stats.Overview.LastMessageAt = endTime

	dateSet := make(map[string]struct{})      // 跟踪参与日期
	tokenMaps := map[string]map[string]int{}  // 每人词频
	responseBuckets := map[string][]float64{} // 回复耗时
	lastMsg := messages[0]
	longestGap := 0.0 // 最长沉默

	for idx, msg := range messages {
		sideKey := participantKey(msg)
		side := ensureSide(stats.Participants, sideKey)
		side.Messages++
		stats.Overview.TotalMessages++

		if msg.Type == model.MessageTypeText || msg.Content != "" {
			charCount := len([]rune(msg.Content))
			side.Characters += charCount
			for _, token := range tokenize(msg.Content) {
				side.Words++
				tokenMap := tokenMaps[sideKey]
				if tokenMap == nil {
					tokenMap = make(map[string]int)
					tokenMaps[sideKey] = tokenMap
				}
				tokenMap[token]++
			}
		}

		// 小时 & 星期分布
		slot := msg.Time.Hour()
		stats.Activity.Hourly[slot]++
		stats.Activity.Weekly[msg.Time.Weekday()]++
		dateSet[msg.Time.Format("2006-01-02")] = struct{}{}

		stats.Content.MediaCounts[mediaLabel(msg)]++

		// 统计相邻消息时间间隔，用于“最长沉默”。
		if idx > 0 {
			gap := msg.Time.Sub(messages[idx-1].Time).Seconds()
			if gap > longestGap {
				longestGap = gap
			}
		}

		if idx == 0 {
			continue
		}
		if msg.IsSelf == lastMsg.IsSelf {
			continue
		}
		delta := msg.Time.Sub(lastMsg.Time).Seconds()
		label := sideKey
		responseBuckets[label] = append(responseBuckets[label], delta)
		lastMsg = msg
	}

	conversationDays := len(dateSet)
	if conversationDays == 0 {
		conversationDays = 1
	}
	stats.Overview.ConversationDays = conversationDays
	stats.Overview.AveragePerDay = float64(stats.Overview.TotalMessages) / float64(conversationDays)
	stats.Response.LongestGapSeconds = longestGap

	for label, side := range stats.Participants {
		side.AveragePerDay = float64(side.Messages) / float64(conversationDays)
		stats.Overview.ParticipantShare[label] = float64(side.Messages) / float64(stats.Overview.TotalMessages)
		side.KeywordPreview = topKeywords(tokenMaps[label], 5)
	}

	for label, durations := range responseBuckets {
		if len(durations) == 0 {
			continue
		}
		sort.Float64s(durations)
		sum := 0.0
		for _, d := range durations {
			sum += d
		}
		stats.Response.AverageSeconds[label] = sum / float64(len(durations))
		stats.Response.MedianSeconds[label] = durations[len(durations)/2]
		stats.Response.MinSeconds[label] = durations[0]
		stats.Response.MaxSeconds[label] = durations[len(durations)-1]
	}

	return stats
}

func participantKey(msg *model.Message) string {
	if msg.IsSelf {
		if msg.SenderName != "" {
			return msg.SenderName
		}
		return "self"
	}
	if msg.SenderName != "" {
		return msg.SenderName
	}
	if msg.TalkerName != "" {
		return msg.TalkerName
	}
	return msg.Talker
}

func ensureSide(m map[string]*Side, key string) *Side {
	if side, ok := m[key]; ok {
		return side
	}
	side := &Side{Label: key}
	m[key] = side
	return side
}

func tokenize(content string) []string {
	var tokens []string
	var sb strings.Builder
	flush := func() {
		if sb.Len() > 1 {
			tokens = append(tokens, sb.String())
		}
		sb.Reset()
	}
	for _, r := range content {
		if unicode.IsLetter(r) || unicode.IsDigit(r) {
			sb.WriteRune(unicode.ToLower(r))
		} else {
			flush()
		}
	}
	flush()
	return tokens
}

func topKeywords(freq map[string]int, limit int) []KeywordStat {
	if len(freq) == 0 {
		return nil
	}
	items := make([]KeywordStat, 0, len(freq))
	for k, v := range freq {
		items = append(items, KeywordStat{Keyword: k, Count: v})
	}
	sort.Slice(items, func(i, j int) bool {
		if items[i].Count == items[j].Count {
			return items[i].Keyword < items[j].Keyword
		}
		return items[i].Count > items[j].Count
	})
	if len(items) > limit {
		items = items[:limit]
	}
	return items
}

func mediaLabel(msg *model.Message) string {
	switch msg.Type {
	case model.MessageTypeText:
		return "text"
	case model.MessageTypeImage:
		return "image"
	case model.MessageTypeVoice:
		return "voice"
	case model.MessageTypeVideo:
		return "video"
	case model.MessageTypeShare:
		switch msg.SubType {
		case model.MessageSubTypeFile:
			return "file"
		default:
			return "share"
		}
	default:
		return "other"
	}
}
