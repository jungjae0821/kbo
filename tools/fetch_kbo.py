"""Python 3.10+, standard library only. Default: 2026 KBO regular season.

Run: python -m tools.fetch_kbo
Fetches all completed regular-season games; resumes from validated local files.
"""
import argparse
import getpass
import json
import os
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, build_opener, HTTPRedirectHandler

BASE = 'https://api.sportradar.com/baseball/trial/v2/ko'


class APIError(RuntimeError):
    def __init__(self, status, message):
        super().__init__(message)
        self.status = status


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None  # Do not forward the API key to a redirect target.


class Client:
    def __init__(self, key):
        self.key = key
        self.last_request = 0.0
        self.opener = build_opener(NoRedirect())

    def get(self, path, **params):
        url = f'{BASE}/{path}.json'
        if params:
            url += '?' + urlencode(params)
        for attempt in range(3):
            time.sleep(max(0, 1.1 - (time.monotonic() - self.last_request)))
            self.last_request = time.monotonic()
            req = Request(url, headers={'x-api-key': self.key, 'Accept': 'application/json'})
            try:
                with self.opener.open(req, timeout=40) as response:
                    payload = json.load(response)
                    if not isinstance(payload, dict):
                        raise RuntimeError('API 응답이 JSON 객체가 아닙니다.')
                    return payload
            except HTTPError as exc:
                status = exc.code
                retry_after = exc.headers.get('Retry-After', '')
                exc.close()
                if status == 429 and attempt < 2:
                    delay = min(60, max(2, int(retry_after))) if retry_after.isdigit() else 2 ** (attempt + 1)
                    time.sleep(delay)
                    continue
                hint = {
                    401: 'API 키를 확인하세요.',
                    403: '키, Global Baseball 체험 활성화 및 접근 권한을 확인하세요.',
                    404: 'ID 또는 엔드포인트를 확인하세요.',
                    429: '호출 한도를 확인하고 잠시 후 다시 실행하세요.',
                }.get(status, '잠시 후 다시 시도하거나 상품 상태를 확인하세요.')
                raise APIError(status, f'HTTP {status}: {hint}') from None
            except (URLError, TimeoutError):
                raise RuntimeError('네트워크 연결 실패 또는 시간 초과입니다.') from None
            except (ValueError, UnicodeError):
                raise RuntimeError('API가 유효한 JSON을 반환하지 않았습니다.') from None


def write_json(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_suffix('.tmp')
    temp.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    temp.replace(path)


def pages(client, path, field, limit=200, max_pages=30, raw_dir=None):
    """Bound pagination so malformed responses cannot exhaust the trial quota."""
    seen_pages = set()
    for page in range(max_pages):
        data = client.get(path, start=page * limit, limit=limit)
        raw_path = None
        if raw_dir is not None:
            raw_path = raw_dir / f'{field}_{page:03d}.json'
            write_json(raw_path, data)
        rows = data.get(field)
        if not isinstance(rows, list):
            keys = ', '.join(data.keys())
            location = f' 원본: {raw_path}' if raw_path else ''
            raise RuntimeError(f'응답에 {field} 배열이 없습니다. 응답 키: {keys}.{location}')
        if rows:
            signature = json.dumps(rows, sort_keys=True)
            if signature in seen_pages:
                raise RuntimeError('같은 페이지가 반복되어 요청을 중단했습니다.')
            seen_pages.add(signature)
        yield rows
        if len(rows) < limit:
            return
    raise RuntimeError('페이지 탐색 상한에 도달했습니다. 시즌 및 응답을 확인하세요.')


def regular_closed(summary):
    event = summary.get('sport_event', {})
    phase = event.get('sport_event_context', {}).get('stage', {}).get('phase')
    return (summary.get('sport_event_status', {}).get('status') == 'closed'
            and phase == 'regular season')


def extract_players(game):
    """Retain actual field names and values; never replace absent statistics with zero."""
    teams = game.get('statistics', {}).get('totals', {}).get('competitors', [])
    records = []
    for team in teams:
        for player in team.get('players', []):
            stats = player.get('statistics')
            if isinstance(stats, dict) and stats:
                records.append({
                    'team_id': team.get('id'), 'team_name': team.get('name'),
                    'player_id': player.get('id'), 'player_name': player.get('name'),
                    'type': player.get('type'), 'statistics': stats,
                })
    return records


def read_cached_game(path, event_id):
    """A raw, closed game with player records is sufficient to rebuild derived data."""
    try:
        game = json.loads(path.read_text(encoding='utf-8'))
        if (game.get('sport_event', {}).get('id') == event_id
                and regular_closed(game) and extract_players(game)):
            return game
    except (OSError, ValueError, AttributeError, TypeError):
        pass
    return None


def save_players(event_folder, game, season):
    records = extract_players(game)
    write_json(event_folder / 'player_stats.json', {
        'retrieved_at': datetime.now(timezone.utc).isoformat(),
        'season': season, 'sport_event': game['sport_event'],
        'sport_event_status': game.get('sport_event_status'),
        'record_scope': 'single_game', 'players': records,
    })
    return len(records)


def save_progress(folder, season, entries, list_complete=True):
    counts = {status: sum(e['status'] == status for e in entries.values())
              for status in ('pending', 'complete', 'no_player_stats', 'failed')}
    report = {
        'updated_at': datetime.now(timezone.utc).isoformat(),
        'season': season, 'scope': 'closed_regular_season',
        'game_list_complete': list_complete,
        'total_games': len(entries), 'counts': counts,
        'all_complete': list_complete and bool(entries) and counts['complete'] == len(entries),
        'games': list(entries.values()),
    }
    write_json(folder / 'collection_status.json', report)
    return report


def collect_games(client, season, folder, max_games=0, refresh=False):
    season_id = season['id']
    summaries = {}
    entries = {}
    # Invalidate an earlier success report until the full, current list is known.
    save_progress(folder, season, entries, list_complete=False)
    for batch in pages(client, f'seasons/{season_id}/summaries', 'summaries',
                       raw_dir=folder / 'raw'):
        for summary in batch:
            if not regular_closed(summary):
                continue
            event_id = summary['sport_event']['id']
            # Validate the API identifier before using it in paths or requests.
            if not event_id.startswith('sr:sport_event:') or not event_id.rsplit(':', 1)[-1].isdigit():
                raise RuntimeError('올바르지 않은 경기 ID를 받았습니다.')
            summaries[event_id] = summary
            entries[event_id] = {'event_id': event_id, 'status': 'pending'}
        save_progress(folder, season, entries, list_complete=False)
    # Inspect every cached game first so a per-run limit does not hide saved games.
    for event_id in summaries:
        event_folder = folder / event_id.replace(':', '_')
        cached = None if refresh else read_cached_game(event_folder / 'game_raw.json', event_id)
        if cached is not None:
            count = save_players(event_folder, cached, season)
            entries[event_id].update(status='complete', player_records=count)
    save_progress(folder, season, entries)
    pending = sum(e['status'] == 'pending' for e in entries.values())
    print(f'종료된 정규리그 {len(entries)}경기 / 저장 완료 {len(entries) - pending} / 수집 대상 {pending}')
    attempted = 0
    for event_id in summaries:
        entry = entries[event_id]
        if entry['status'] == 'complete':
            continue
        if max_games and attempted >= max_games:
            break
        attempted += 1
        event_folder = folder / event_id.replace(':', '_')
        try:
            game = client.get(f'sport_events/{event_id}/summary')
            if game.get('sport_event', {}).get('id') != event_id or not regular_closed(game):
                raise RuntimeError('상세 응답의 경기 ID 또는 정규리그 종료 상태가 일치하지 않습니다.')
            write_json(event_folder / 'game_raw.json', game)
            count = save_players(event_folder, game, season)
            entry.update(status='complete' if count else 'no_player_stats', player_records=count)
            print(f'[{attempted}/{pending}] {event_id}: 선수 기록 {count}건')
        except (RuntimeError, KeyError, TypeError, ValueError) as exc:
            entry.update(status='failed', error=str(exc))
            print(f'{event_id}: {exc}', file=sys.stderr)
            # Do not consume the rest of the quota after an account-wide rejection.
            if isinstance(exc, APIError) and exc.status in (401, 403, 429):
                save_progress(folder, season, entries)
                raise
        # Persist after each game; a forced interruption only loses this request.
        save_progress(folder, season, entries)
    report = save_progress(folder, season, entries)
    print(f"수집 현황: {report['counts']} / 전체 {report['total_games']}경기")
    print(f"현황 파일: {folder / 'collection_status.json'}")
    if not report['all_complete']:
        print('미완료 경기가 있습니다. 같은 명령을 다시 실행하면 이어받습니다.')
    return report


def run(client, year, output, max_games=0, refresh=False):
    competitions = client.get('competitions').get('competitions', [])
    # Use the main league ID observed in the API response. Preseason and
    # All Star Game are separate competitions whose names also contain KBO.
    matches = [c for c in competitions if c.get('id') == 'sr:competition:2541']
    if not matches:
        matches = [c for c in competitions
                   if c.get('name', '').strip().casefold() == 'kbo league']
    if len(matches) != 1:
        options = ', '.join(f"{c.get('name')} ({c.get('id')})" for c in competitions
                            if 'kbo' in c.get('name', '').casefold())
        raise RuntimeError('KBO 1군 대회를 하나로 식별하지 못했습니다. 후보: ' + (options or '없음'))
    competition = matches[0]
    seasons = client.get(f"competitions/{competition['id']}/seasons").get('seasons', [])
    available = ', '.join(str(s.get('year')) for s in seasons)
    matches = [s for s in seasons if str(s.get('year')) == str(year) and not s.get('disabled')]
    if len(matches) != 1:
        raise RuntimeError(f'{year} 시즌을 하나로 선택하지 못했습니다. 제공 시즌: {available}')
    season = matches[0]
    season_id = season['id']
    folder = output / f"kbo_{year}_{season_id.rsplit(':', 1)[-1]}"
    print(f"대회: {competition['name']} / 시즌: {season.get('name', year)}")
    teams = []
    for batch in pages(client, f'seasons/{season_id}/competitors', 'season_competitors',
                       limit=1000, raw_dir=folder / 'raw'):
        teams.extend(batch)
    if not teams:
        raise RuntimeError('팀 목록이 비어 있습니다.')
    write_json(folder / 'teams.json', {'competition': competition, 'season': season, 'competitors': teams})
    print(f"팀 {len(teams)}개 저장: {folder / 'teams.json'}")
    return collect_games(client, season, folder, max_games, refresh)


def main():
    parser = argparse.ArgumentParser(description='Sportradar KBO 정규리그 종료 경기 전체 수집 및 이어받기')
    parser.add_argument('--season', type=int, default=2026, help='시즌 연도 (기본 2026, 정규리그 경기만 조회)')
    parser.add_argument('--output', type=Path, default=Path(__file__).resolve().parent.parent / 'kbo_data')
    parser.add_argument('--max-games', type=int, default=0, help='이번 실행에서 조회할 상세 경기 수 (기본 0: 전체, 저장된 경기는 제외)')
    parser.add_argument('--refresh', action='store_true', help='저장된 경기 상세도 API에서 다시 받기')
    args = parser.parse_args()
    if args.max_games < 0:
        parser.error('--max-games는 0 이상이어야 합니다.')
    key = os.environ.get('SPORTRADAR_API_KEY', '').strip()
    if not key:
        key = getpass.getpass('Sportradar API 키 (화면에 표시되지 않음): ').strip()
    if not key:
        parser.exit(1, 'API 키가 비어 있습니다.\n')
    try:
        report = run(Client(key), args.season, args.output.resolve(), args.max_games, args.refresh)
    except (RuntimeError, OSError, KeyError, TypeError) as exc:
        print(f'실패: {exc}', file=sys.stderr)
        return 1
    return 0 if report['all_complete'] else 2


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (KeyboardInterrupt, EOFError):
        sys.exit('\n실행을 중단했습니다.')
