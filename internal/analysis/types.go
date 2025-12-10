package analysis

import "time"

// PairStats represents statistics computed for a conversation between
// the current user and a specific talker. 这是主输出结构。
type PairStats struct {
	Talker       string            `json:"talker"`       // 联系人 ID
	TimeStart    time.Time         `json:"timeStart"`    // 统计起点
	TimeEnd      time.Time         `json:"timeEnd"`      // 统计终点
	Participants map[string]*Side  `json:"participants"` // “我/对方”视角
	Overview     *Overview         `json:"overview"`     // 概览指标
	Activity     *Activity         `json:"activity"`     // 活跃时间
	Response     *ResponseInsights `json:"response"`     // 回复时延
	Content      *ContentBreakdown `json:"content"`      // 媒体占比
}

// Side summarises metrics for one participant (self vs contact).
type Side struct {
	Label          string        `json:"label"`         // 显示名称
	Messages       int           `json:"messages"`      // 消息数
	Characters     int           `json:"characters"`    // 字符数
	Words          int           `json:"words"`         // 词数
	AveragePerDay  float64       `json:"averagePerDay"` // 日均消息
	KeywordPreview []KeywordStat `json:"keywordPreview"`
}

// KeywordStat holds a keyword and its frequency.
type KeywordStat struct {
	Keyword string `json:"keyword"`
	Count   int    `json:"count"`
}

// Overview describes conversation scale.
type Overview struct {
	TotalMessages    int                `json:"totalMessages"`    // 消息总数
	ConversationDays int                `json:"conversationDays"` // 活跃天数
	FirstMessageAt   time.Time          `json:"firstMessageAt"`
	LastMessageAt    time.Time          `json:"lastMessageAt"`
	AveragePerDay    float64            `json:"averagePerDay"`
	ParticipantShare map[string]float64 `json:"participantShare"` // 双方占比
}

// Activity represents temporal distributions.
type Activity struct {
	Hourly map[int]int          `json:"hourly"` // 按小时段聚合
	Weekly map[time.Weekday]int `json:"weekly"` // 按星期聚合
}

// ResponseInsights contains response time analytics.
type ResponseInsights struct {
	AverageSeconds    map[string]float64 `json:"averageSeconds"`
	MedianSeconds     map[string]float64 `json:"medianSeconds"`
	MinSeconds        map[string]float64 `json:"minSeconds"`
	MaxSeconds        map[string]float64 `json:"maxSeconds"`
	LongestGapSeconds float64            `json:"longestGapSeconds"`
}

// ContentBreakdown summarises message-type usage.
type ContentBreakdown struct {
	MediaCounts map[string]int `json:"mediaCounts"`
}
