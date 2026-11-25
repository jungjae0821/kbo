// season_dataset.json의 팀 기록에서 계산 (승률 = 승 / (승 + 패), 무승부 제외)
window.STANDINGS = [
  { r: 1, t: 'KT', n: 'KT 위즈', g: 144, w: 90, l: 49, d: 5, pct: '0.647', gb: '0.0', avg: '0.286', era: '4.14' },
  { r: 2, t: '삼성', n: '삼성 라이온즈', g: 144, w: 83, l: 58, d: 3, pct: '0.589', gb: '8.0', avg: '0.273', era: '4.31' },
  { r: 3, t: 'KIA', n: 'KIA 타이거즈', g: 144, w: 79, l: 63, d: 2, pct: '0.556', gb: '12.5', avg: '0.271', era: '4.27' },
  { r: 4, t: 'LG', n: 'LG 트윈스', g: 144, w: 78, l: 65, d: 1, pct: '0.545', gb: '14.0', avg: '0.264', era: '4.81' },
  { r: 5, t: '두산', n: '두산 베어스', g: 144, w: 73, l: 66, d: 5, pct: '0.525', gb: '17.0', avg: '0.267', era: '3.86' },
  { r: 6, t: 'SSG', n: 'SSG 랜더스', g: 144, w: 65, l: 74, d: 5, pct: '0.468', gb: '25.0', avg: '0.259', era: '5.16' },
  { r: 7, t: '롯데', n: '롯데 자이언츠', g: 144, w: 64, l: 77, d: 3, pct: '0.454', gb: '27.0', avg: '0.272', era: '4.72' },
  { r: 8, t: 'NC', n: 'NC 다이노스', g: 144, w: 64, l: 78, d: 2, pct: '0.451', gb: '27.5', avg: '0.270', era: '4.79' },
  { r: 9, t: '한화', n: '한화 이글스', g: 144, w: 57, l: 83, d: 4, pct: '0.407', gb: '33.5', avg: '0.273', era: '5.26' },
  { r: 10, t: '키움', n: '키움 히어로즈', g: 144, w: 50, l: 90, d: 4, pct: '0.357', gb: '40.5', avg: '0.244', era: '5.30' },
];
window.COLS = [
  ['pct', '승률'], ['gb', '게임차'], ['g', '경기'], ['w', '승'], ['l', '패'], ['d', '무'], ['avg', '타율'], ['era', '평균<br>자책'],
];
window.renderTable = function (el) {
  const head = '<tr><th class="c-rank" scope="col">순위</th><th class="c-team" scope="col">팀</th>' +
    COLS.map(([k, n]) => `<th scope="col" class="c-${k}">${n}</th>`).join('') + '</tr>';
  const body = STANDINGS.map(s =>
    `<tr><td class="c-rank">${s.r}</td><th scope="row" class="c-team">${s.t}</th>` +
    COLS.map(([k]) => `<td class="c-${k}">${s[k]}</td>`).join('') + '</tr>').join('');
  const cols = '<colgroup><col class="c-rank"><col class="c-team">' + COLS.map(([k]) => `<col class="c-${k}">`).join('') + '</colgroup>';
  el.innerHTML = `<table>${cols}<thead>${head}</thead><tbody>${body}</tbody></table>`;
};
