const adjectives = ["pretty", "large", "big", "small", "tall", "short", "long", "handsome", "plain", "quaint", "clean", "elegant", "easy", "angry", "crazy", "helpful", "mushy", "odd", "unsightly", "adorable", "important", "inexpensive", "cheap", "expensive", "fancy"]; // prettier-ignore
const colors = ["red", "yellow", "blue", "green", "pink", "brown", "purple", "brown", "white", "black", "orange"]; // prettier-ignore
const nouns = ["table", "chair", "house", "bbq", "desk", "car", "pony", "cookie", "sandwich", "burger", "pizza", "mouse", "keyboard"]; // prettier-ignore

export interface Row {
  id: number;
  label: string;
}

const random = (max: number) => Math.round(Math.random() * 1000) % max;

export function build(from: number, count: number): Row[] {
  const data = new Array<Row>(count);
  for (let i = 0; i < count; i++) {
    data[i] = {
      id: from + i,
      label: `${adjectives[random(adjectives.length)]} ${colors[random(colors.length)]} ${nouns[random(nouns.length)]}`,
    };
  }
  return data;
}

export function update(rows: Row[]): Row[] {
  const next = rows.slice();
  for (let i = 0; i < next.length; i += 10) next[i] = { id: next[i].id, label: `${next[i].label} !!!` };
  return next;
}

export function swap(rows: Row[]): Row[] {
  if (rows.length <= 998) return rows;
  const next = rows.slice();
  const item = next[1];
  next[1] = next[998];
  next[998] = item;
  return next;
}

export function remove(rows: Row[], id: number): Row[] {
  return rows.toSpliced(rows.findIndex((r) => r.id === id), 1);
}
