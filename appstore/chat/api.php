<?php
header('Content-Type: application/json; charset=utf-8');

define('CHAT_DATA_FILE', __DIR__ . '/chat-data.json');
define('MAX_MESSAGES_PER_CHANNEL', 3000);
define('MAX_DM_MESSAGES_PER_THREAD', 800);
define('MAX_MESSAGE_AGE_MS', 21 * 24 * 60 * 60 * 1000);

define('RATE_LIMITS', [
    'session' => ['window' => 60, 'max' => 30],
    'status' => ['window' => 60, 'max' => 180],
    'join' => ['window' => 60, 'max' => 40],
    'leave' => ['window' => 60, 'max' => 40],
    'messages' => ['window' => 60, 'max' => 180],
    'send' => ['window' => 60, 'max' => 35],
    'dm_messages' => ['window' => 60, 'max' => 180],
    'dm_send' => ['window' => 60, 'max' => 35]
]);

action_dispatch();

function action_dispatch(): void {
    $action = $_GET['action'] ?? '';

    enforce_rate_limit($action);

    try {
        switch ($action) {
            case 'session':
                session_action();
                return;
            case 'status':
                status_action();
                return;
            case 'join':
                join_action();
                return;
            case 'leave':
                leave_action();
                return;
            case 'messages':
                messages_action();
                return;
            case 'send':
                send_action();
                return;
            case 'dm_messages':
                dm_messages_action();
                return;
            case 'dm_send':
                dm_send_action();
                return;
            default:
                respond(['error' => 'unknown_action'], 400);
                return;
        }
    } catch (Throwable $e) {
        respond(['error' => 'server_error', 'detail' => $e->getMessage()], 500);
    }
}

function read_json_body(): array {
    $raw = file_get_contents('php://input');
    if (!$raw) {
        return [];
    }

    $decoded = json_decode($raw, true);
    if (!is_array($decoded)) {
        return [];
    }

    return $decoded;
}

function load_data(): array {
    if (!file_exists(CHAT_DATA_FILE)) {
        return [
            'users' => [],
            'memberships' => [],
            'messages' => [],
            'dmMessages' => [],
            'rateLimits' => []
        ];
    }

    $raw = file_get_contents(CHAT_DATA_FILE);
    if (!$raw) {
        return [
            'users' => [],
            'memberships' => [],
            'messages' => [],
            'dmMessages' => [],
            'rateLimits' => []
        ];
    }

    $decoded = json_decode($raw, true);
    if (!is_array($decoded)) {
        return [
            'users' => [],
            'memberships' => [],
            'messages' => [],
            'dmMessages' => [],
            'rateLimits' => []
        ];
    }

    $decoded['users'] = is_array($decoded['users'] ?? null) ? $decoded['users'] : [];
    $decoded['memberships'] = is_array($decoded['memberships'] ?? null) ? $decoded['memberships'] : [];
    $decoded['messages'] = is_array($decoded['messages'] ?? null) ? $decoded['messages'] : [];
    $decoded['dmMessages'] = is_array($decoded['dmMessages'] ?? null) ? $decoded['dmMessages'] : [];
    $decoded['rateLimits'] = is_array($decoded['rateLimits'] ?? null) ? $decoded['rateLimits'] : [];
    return $decoded;
}

function save_data(array $data): void {
    $fp = fopen(CHAT_DATA_FILE, 'c+');
    if (!$fp) {
        throw new RuntimeException('cannot_open_data_file');
    }

    if (!flock($fp, LOCK_EX)) {
        fclose($fp);
        throw new RuntimeException('cannot_lock_data_file');
    }

    ftruncate($fp, 0);
    rewind($fp);
    fwrite($fp, json_encode($data, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE));
    fflush($fp);
    flock($fp, LOCK_UN);
    fclose($fp);
}

function now_ms(): int {
    return (int) round(microtime(true) * 1000);
}

function random_id(string $prefix): string {
    return $prefix . bin2hex(random_bytes(8));
}

function sanitize_text(string $text, int $maxLen = 400): string {
    $trimmed = trim($text);
    if (mb_strlen($trimmed) > $maxLen) {
        $trimmed = mb_substr($trimmed, 0, $maxLen);
    }
    return $trimmed;
}

function require_field(array $body, string $name): string {
    $value = trim((string) ($body[$name] ?? ''));
    if ($value === '') {
        respond(['error' => 'missing_' . $name], 400);
    }
    return $value;
}

function ensure_user(array &$data, string $userId, string $alias): array {
    if (!isset($data['users'][$userId])) {
        $data['users'][$userId] = [
            'userId' => $userId,
            'alias' => $alias,
            'createdAt' => now_ms()
        ];
    }

    return $data['users'][$userId];
}

function validate_festival_id(string $festivalId): string {
    if (!preg_match('/^[a-z0-9][a-z0-9._:-]{1,63}$/i', $festivalId)) {
        respond(['error' => 'invalid_festivalId'], 400);
    }
    return $festivalId;
}

function validate_user_id(string $userId): string {
    if (!preg_match('/^[a-z0-9][a-z0-9_-]{2,31}$/i', $userId)) {
        respond(['error' => 'invalid_userId'], 400);
    }
    return $userId;
}

function validate_alias(string $alias): string {
    $clean = sanitize_text($alias, 24);
    if (!preg_match('/^[A-Za-z0-9_-]{3,24}$/', $clean)) {
        respond(['error' => 'invalid_alias'], 400);
    }
    return $clean;
}

function client_key(): string {
    $ip = (string) ($_SERVER['REMOTE_ADDR'] ?? 'unknown');
    return preg_replace('/[^a-fA-F0-9:.]/', '', $ip) ?: 'unknown';
}

function enforce_rate_limit(string $action): void {
    if (!isset(RATE_LIMITS[$action])) {
        return;
    }

    $rule = RATE_LIMITS[$action];
    $windowSec = (int) $rule['window'];
    $max = (int) $rule['max'];
    $now = time();

    $data = load_data();
    $key = client_key();

    if (!isset($data['rateLimits'][$key])) {
        $data['rateLimits'][$key] = [];
    }
    if (!isset($data['rateLimits'][$key][$action])) {
        $data['rateLimits'][$key][$action] = ['windowStart' => $now, 'count' => 0];
    }

    $bucket = $data['rateLimits'][$key][$action];
    $windowStart = (int) ($bucket['windowStart'] ?? $now);
    $count = (int) ($bucket['count'] ?? 0);

    if (($now - $windowStart) >= $windowSec) {
        $windowStart = $now;
        $count = 0;
    }

    $count += 1;
    $data['rateLimits'][$key][$action] = ['windowStart' => $windowStart, 'count' => $count];

    cleanup_rate_limits($data, $now, $windowSec * 3);
    save_data($data);

    if ($count > $max) {
        respond(['error' => 'rate_limited'], 429);
    }
}

function cleanup_rate_limits(array &$data, int $now, int $maxAgeSec): void {
    foreach ($data['rateLimits'] as $ip => $actions) {
        if (!is_array($actions)) {
            unset($data['rateLimits'][$ip]);
            continue;
        }

        foreach ($actions as $action => $bucket) {
            $windowStart = (int) ($bucket['windowStart'] ?? 0);
            if ($windowStart <= 0 || ($now - $windowStart) > $maxAgeSec) {
                unset($data['rateLimits'][$ip][$action]);
            }
        }

        if (empty($data['rateLimits'][$ip])) {
            unset($data['rateLimits'][$ip]);
        }
    }
}

function cleanup_old_messages(array &$data): void {
    $minCreatedAt = now_ms() - MAX_MESSAGE_AGE_MS;
    foreach ($data['messages'] as $festivalId => $messages) {
        if (!is_array($messages)) {
            unset($data['messages'][$festivalId]);
            continue;
        }

        $filtered = array_values(array_filter($messages, static function ($message) use ($minCreatedAt) {
            return ((int) ($message['createdAt'] ?? 0)) >= $minCreatedAt;
        }));

        if (count($filtered) > MAX_MESSAGES_PER_CHANNEL) {
            $filtered = array_slice($filtered, -MAX_MESSAGES_PER_CHANNEL);
        }

        $data['messages'][$festivalId] = $filtered;
    }

    foreach ($data['dmMessages'] as $threadId => $messages) {
        if (!is_array($messages)) {
            unset($data['dmMessages'][$threadId]);
            continue;
        }

        $filtered = array_values(array_filter($messages, static function ($message) use ($minCreatedAt) {
            return ((int) ($message['createdAt'] ?? 0)) >= $minCreatedAt;
        }));

        if (count($filtered) > MAX_DM_MESSAGES_PER_THREAD) {
            $filtered = array_slice($filtered, -MAX_DM_MESSAGES_PER_THREAD);
        }

        $data['dmMessages'][$threadId] = $filtered;
    }
}

function dm_thread_id(string $userA, string $userB): string {
    $pair = [$userA, $userB];
    sort($pair, SORT_STRING);
    return $pair[0] . '__' . $pair[1];
}

function dm_peer_alias(array $data, string $peerUserId): string {
    $fallback = 'Usuario';
    if (!isset($data['users'][$peerUserId])) {
        return $fallback;
    }
    $alias = (string) ($data['users'][$peerUserId]['alias'] ?? '');
    return $alias !== '' ? $alias : $fallback;
}

function join_membership(array &$data, string $festivalId, string $userId): array {
    if (!isset($data['memberships'][$festivalId])) {
        $data['memberships'][$festivalId] = [];
    }

    $joinedAt = now_ms();
    $data['memberships'][$festivalId][$userId] = [
        'joinedAt' => $joinedAt,
        'notificationMode' => 'mentionsOnly'
    ];

    return $data['memberships'][$festivalId][$userId];
}

function session_action(): void {
    $body = read_json_body();
    $userId = trim((string) ($body['userId'] ?? ''));
    $alias = trim((string) ($body['alias'] ?? ''));

    if ($userId === '') {
        $userId = random_id('u-');
    }
    if ($alias === '') {
        $alias = 'Festi' . substr($userId, -4);
    }

    $userId = validate_user_id($userId);
    $alias = validate_alias($alias);

    $data = load_data();
    $user = ensure_user($data, $userId, $alias);
    save_data($data);

    respond([
        'userId' => $user['userId'],
        'alias' => $user['alias']
    ]);
}

function status_action(): void {
    $body = read_json_body();
    $festivalId = validate_festival_id(require_field($body, 'festivalId'));
    $userId = validate_user_id(require_field($body, 'userId'));

    $data = load_data();
    $joined = isset($data['memberships'][$festivalId][$userId]);

    respond(['joined' => $joined]);
}

function join_action(): void {
    $body = read_json_body();
    $festivalId = validate_festival_id(require_field($body, 'festivalId'));
    $userId = validate_user_id(require_field($body, 'userId'));
    $alias = validate_alias(require_field($body, 'alias'));

    $data = load_data();
    ensure_user($data, $userId, $alias);
    join_membership($data, $festivalId, $userId);
    save_data($data);

    respond(['joined' => true]);
}

function leave_action(): void {
    $body = read_json_body();
    $festivalId = validate_festival_id(require_field($body, 'festivalId'));
    $userId = validate_user_id(require_field($body, 'userId'));

    $data = load_data();
    if (isset($data['memberships'][$festivalId][$userId])) {
        unset($data['memberships'][$festivalId][$userId]);
    }
    save_data($data);

    respond(['joined' => false]);
}

function messages_action(): void {
    $body = read_json_body();
    $festivalId = validate_festival_id(require_field($body, 'festivalId'));
    $userId = validate_user_id(require_field($body, 'userId'));

    $data = load_data();
    $membership = $data['memberships'][$festivalId][$userId] ?? null;
    if (!$membership) {
        respond(['messages' => []]);
    }

    $joinedAt = (int) ($membership['joinedAt'] ?? 0);
    $all = $data['messages'][$festivalId] ?? [];

    $filtered = array_values(array_filter($all, static function ($message) use ($joinedAt) {
        return ((int) ($message['createdAt'] ?? 0)) >= $joinedAt;
    }));

    if (count($filtered) > 200) {
        $filtered = array_slice($filtered, -200);
    }

    respond(['messages' => $filtered]);
}

function extract_mentions(string $text, array $users): array {
    preg_match_all('/@([A-Za-z0-9_-]{3,24})/', $text, $matches);
    $aliases = $matches[1] ?? [];
    if (!$aliases) {
        return [];
    }

    $mentions = [];
    foreach ($users as $user) {
        $alias = (string) ($user['alias'] ?? '');
        $userId = (string) ($user['userId'] ?? '');
        if ($alias === '' || $userId === '') {
            continue;
        }
        foreach ($aliases as $candidate) {
            if (strcasecmp($candidate, $alias) === 0) {
                $mentions[] = $userId;
                break;
            }
        }
    }

    return array_values(array_unique($mentions));
}

function send_action(): void {
    $body = read_json_body();
    $festivalId = validate_festival_id(require_field($body, 'festivalId'));
    $userId = validate_user_id(require_field($body, 'userId'));
    $alias = validate_alias(require_field($body, 'alias'));
    $text = sanitize_text(require_field($body, 'text'));

    if ($text === '') {
        respond(['error' => 'empty_message'], 400);
    }

    $data = load_data();
    ensure_user($data, $userId, $alias);

    if (!isset($data['memberships'][$festivalId][$userId])) {
        join_membership($data, $festivalId, $userId);
    }

    if (!isset($data['messages'][$festivalId])) {
        $data['messages'][$festivalId] = [];
    }

    cleanup_old_messages($data);

    $message = [
        'id' => random_id('m-'),
        'festivalId' => $festivalId,
        'userId' => $userId,
        'alias' => $data['users'][$userId]['alias'],
        'text' => $text,
        'mentions' => extract_mentions($text, $data['users']),
        'createdAt' => now_ms()
    ];

    $data['messages'][$festivalId][] = $message;

    if (count($data['messages'][$festivalId]) > MAX_MESSAGES_PER_CHANNEL) {
        $data['messages'][$festivalId] = array_slice($data['messages'][$festivalId], -MAX_MESSAGES_PER_CHANNEL);
    }

    save_data($data);
    respond(['ok' => true, 'message' => $message]);
}

function dm_messages_action(): void {
    $body = read_json_body();
    $userId = validate_user_id(require_field($body, 'userId'));
    $peerUserId = validate_user_id(require_field($body, 'peerUserId'));

    if ($userId === $peerUserId) {
        respond(['messages' => []]);
    }

    $data = load_data();
    $threadId = dm_thread_id($userId, $peerUserId);
    $all = $data['dmMessages'][$threadId] ?? [];
    if (!is_array($all)) {
        $all = [];
    }

    if (count($all) > 200) {
        $all = array_slice($all, -200);
    }

    respond([
        'threadId' => $threadId,
        'peerUserId' => $peerUserId,
        'peerAlias' => dm_peer_alias($data, $peerUserId),
        'messages' => $all
    ]);
}

function dm_send_action(): void {
    $body = read_json_body();
    $userId = validate_user_id(require_field($body, 'userId'));
    $alias = validate_alias(require_field($body, 'alias'));
    $peerUserId = validate_user_id(require_field($body, 'peerUserId'));
    $text = sanitize_text(require_field($body, 'text'));

    if ($userId === $peerUserId) {
        respond(['error' => 'invalid_peerUserId'], 400);
    }

    if ($text === '') {
        respond(['error' => 'empty_message'], 400);
    }

    $data = load_data();
    ensure_user($data, $userId, $alias);

    if (!isset($data['users'][$peerUserId])) {
        $data['users'][$peerUserId] = [
            'userId' => $peerUserId,
            'alias' => 'Festi' . substr($peerUserId, -4),
            'createdAt' => now_ms()
        ];
    }

    cleanup_old_messages($data);

    $threadId = dm_thread_id($userId, $peerUserId);
    if (!isset($data['dmMessages'][$threadId]) || !is_array($data['dmMessages'][$threadId])) {
        $data['dmMessages'][$threadId] = [];
    }

    $message = [
        'id' => random_id('dm-'),
        'threadId' => $threadId,
        'fromUserId' => $userId,
        'fromAlias' => $data['users'][$userId]['alias'],
        'toUserId' => $peerUserId,
        'toAlias' => $data['users'][$peerUserId]['alias'],
        'text' => $text,
        'createdAt' => now_ms()
    ];

    $data['dmMessages'][$threadId][] = $message;
    if (count($data['dmMessages'][$threadId]) > MAX_DM_MESSAGES_PER_THREAD) {
        $data['dmMessages'][$threadId] = array_slice($data['dmMessages'][$threadId], -MAX_DM_MESSAGES_PER_THREAD);
    }

    save_data($data);
    respond(['ok' => true, 'message' => $message]);
}

function respond(array $payload, int $status = 200): void {
    http_response_code($status);
    echo json_encode($payload, JSON_UNESCAPED_UNICODE);
    exit;
}
