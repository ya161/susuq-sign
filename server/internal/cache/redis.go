package cache

import (
	"context"
	"fmt"
	"log"
	"time"

	"github.com/redis/go-redis/v9"
)

// VerifyCodeStore 验证码 + 短信限流存储接口
// 允许运行环境选择 Redis（推荐）或进程内兜底
type VerifyCodeStore interface {
	SetCode(phone, code string, ttl time.Duration) error
	GetCode(phone string) (string, error) // 找不到返回 "", nil
	DeleteCode(phone string) error
	// IncrRateLimit 返回本窗口内当前计数；首次调用时同时设置 TTL
	IncrRateLimit(phone string, window time.Duration) (int64, error)
}

// ====== Redis 实现 ======

type RedisStore struct {
	client *redis.Client
}

// NewRedisStore 基于 Addr(host:port) + 密码 + DB 创建客户端
func NewRedisStore(addr, password string, db int) (*RedisStore, error) {
	client := redis.NewClient(&redis.Options{
		Addr:     addr,
		Password: password,
		DB:       db,
	})
	return pingAndWrap(client, fmt.Sprintf("%s (db=%d)", addr, db))
}

// NewRedisStoreFromURL 基于标准 URL（如 `redis://:pwd@host:6379/0`）创建客户端
// 兼容已有部署中使用的 REDIS_URL 环境变量
func NewRedisStoreFromURL(url string) (*RedisStore, error) {
	opts, err := redis.ParseURL(url)
	if err != nil {
		return nil, fmt.Errorf("解析 REDIS_URL 失败: %w", err)
	}
	return pingAndWrap(redis.NewClient(opts), url)
}

func pingAndWrap(client *redis.Client, label string) (*RedisStore, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	if err := client.Ping(ctx).Err(); err != nil {
		return nil, fmt.Errorf("redis ping 失败: %w", err)
	}
	log.Printf("Redis 已连接: %s", label)
	return &RedisStore{client: client}, nil
}

func smsCodeKey(phone string) string  { return "sms:code:" + phone }
func smsRateKey(phone string) string  { return "sms:rate:" + phone }

func (r *RedisStore) SetCode(phone, code string, ttl time.Duration) error {
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	return r.client.Set(ctx, smsCodeKey(phone), code, ttl).Err()
}

func (r *RedisStore) GetCode(phone string) (string, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	val, err := r.client.Get(ctx, smsCodeKey(phone)).Result()
	if err == redis.Nil {
		return "", nil
	}
	return val, err
}

func (r *RedisStore) DeleteCode(phone string) error {
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	return r.client.Del(ctx, smsCodeKey(phone)).Err()
}

func (r *RedisStore) IncrRateLimit(phone string, window time.Duration) (int64, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	key := smsRateKey(phone)
	count, err := r.client.Incr(ctx, key).Result()
	if err != nil {
		return 0, err
	}
	// 首次 set 时才设 TTL
	if count == 1 {
		if err := r.client.Expire(ctx, key, window).Err(); err != nil {
			return count, err
		}
	}
	return count, nil
}

// ====== 进程内兜底（Redis 不可用时使用）======

type memoryStore struct {
	codes map[string]memoryCode
	rates map[string]memoryRate
	mu    chan struct{}
}

type memoryCode struct {
	code    string
	expires time.Time
}
type memoryRate struct {
	count  int64
	expires time.Time
}

// NewMemoryStore 单进程兜底实现，仅 dev / fallback 使用
func NewMemoryStore() VerifyCodeStore {
	return &memoryStore{
		codes: map[string]memoryCode{},
		rates: map[string]memoryRate{},
		mu:    make(chan struct{}, 1),
	}
}

func (m *memoryStore) lock()   { m.mu <- struct{}{} }
func (m *memoryStore) unlock() { <-m.mu }

func (m *memoryStore) SetCode(phone, code string, ttl time.Duration) error {
	m.lock()
	defer m.unlock()
	m.codes[phone] = memoryCode{code: code, expires: time.Now().Add(ttl)}
	return nil
}

func (m *memoryStore) GetCode(phone string) (string, error) {
	m.lock()
	defer m.unlock()
	entry, ok := m.codes[phone]
	if !ok || time.Now().After(entry.expires) {
		delete(m.codes, phone)
		return "", nil
	}
	return entry.code, nil
}

func (m *memoryStore) DeleteCode(phone string) error {
	m.lock()
	defer m.unlock()
	delete(m.codes, phone)
	return nil
}

func (m *memoryStore) IncrRateLimit(phone string, window time.Duration) (int64, error) {
	m.lock()
	defer m.unlock()
	now := time.Now()
	entry, ok := m.rates[phone]
	if !ok || now.After(entry.expires) {
		m.rates[phone] = memoryRate{count: 1, expires: now.Add(window)}
		return 1, nil
	}
	entry.count++
	m.rates[phone] = entry
	return entry.count, nil
}
