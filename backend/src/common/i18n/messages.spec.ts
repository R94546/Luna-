import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { SUPPORTED_LANGS, dictionaries, parseLang, t } from './messages';

const SRC = join(__dirname, '..', '..');

/** Ключи словаря выглядят как `error.something` или `validation.something`. */
const KEY_PATTERN = /'((?:error|validation)\.[a-z0-9_]+)'/g;

function tsFiles(dir: string): string[] {
  return readdirSync(dir).flatMap((name) => {
    const full = join(dir, name);
    if (statSync(full).isDirectory()) return tsFiles(full);
    return name.endsWith('.ts') && !name.endsWith('.spec.ts') ? [full] : [];
  });
}

/**
 * Ключи, на которые ссылается код.
 *
 * Собираются из исходников, а не перечисляются списком: перечисленный
 * список устаревает ровно тогда, когда нужен, — при добавлении нового
 * сообщения.
 */
function keysUsedInCode(): Map<string, string[]> {
  const usage = new Map<string, string[]>();

  for (const file of tsFiles(SRC)) {
    const source = readFileSync(file, 'utf8');
    for (const match of source.matchAll(KEY_PATTERN)) {
      const key = match[1];
      const where = file.slice(SRC.length + 1).replace(/\\/g, '/');
      usage.set(key, [...(usage.get(key) ?? []), where]);
    }
  }

  return usage;
}

describe('словарь сообщений', () => {
  const usage = keysUsedInCode();
  const keys = [...usage.keys()].sort();

  it('в коде вообще используются ключи', () => {
    // Страховка от сломанного сканера: если regexp перестанет находить
    // ключи, все остальные проверки станут пустыми и молча зелёными.
    expect(keys.length).toBeGreaterThan(20);
  });

  /**
   * Проверяем словарь напрямую, а не через `t()`.
   *
   * `t()` при отсутствии ключа откатывается на язык по умолчанию, поэтому
   * забытый русский перевод через неё выглядит как рабочий — просто отдаёт
   * узбекский текст. Пользователь при этом видит не тот язык, который
   * попросил, и жалобы на это не будет: интерфейс же не сломан.
   */
  describe.each(SUPPORTED_LANGS)('язык %s', (lang) => {
    it('содержит каждый ключ, встречающийся в коде', () => {
      const missing = keys.filter((key) => !(key in dictionaries[lang]));

      expect({ lang, missing }).toEqual({ lang, missing: [] });
    });

    it('не содержит пустых строк', () => {
      const empty = Object.entries(dictionaries[lang])
        .filter(([, value]) => value.trim() === '')
        .map(([key]) => key);

      expect(empty).toEqual([]);
    });

    it('не оставляет неподставленных плейсхолдеров при передаче параметров', () => {
      const withParams = keys.filter((key) => /\{(\w+)\}/.test(t(lang, key)));

      for (const key of withParams) {
        const names = [...t(lang, key).matchAll(/\{(\w+)\}/g)].map((m) => m[1]);
        const params = Object.fromEntries(names.map((n) => [n, 'X']));

        expect(t(lang, key, params)).not.toMatch(/\{\w+\}/);
      }
    });
  });

  /**
   * Языки должны идти вровень. Ключ, добавленный только в узбекский,
   * никак себя не проявит — русский молча отдаст узбекский текст.
   */
  it('узбекский и русский словари содержат одни и те же ключи', () => {
    const uzKeys = Object.keys(dictionaries.uz).sort();
    const ruKeys = Object.keys(dictionaries.ru).sort();

    expect({
      нетВРусском: uzKeys.filter((k) => !(k in dictionaries.ru)),
      нетВУзбекском: ruKeys.filter((k) => !(k in dictionaries.uz)),
    }).toEqual({ нетВРусском: [], нетВУзбекском: [] });
  });

  /** Плейсхолдеры должны совпадать: иначе на одном языке подстановка пропадёт. */
  it('одинаковые плейсхолдеры в обоих языках', () => {
    const placeholders = (text: string) =>
      [...text.matchAll(/\{(\w+)\}/g)].map((m) => m[1]).sort();

    const mismatched = Object.keys(dictionaries.uz)
      .filter((key) => key in dictionaries.ru)
      .filter(
        (key) =>
          placeholders(dictionaries.uz[key]).join() !==
          placeholders(dictionaries.ru[key]).join(),
      );

    expect(mismatched).toEqual([]);
  });

  it('оставляет плейсхолдер, если параметр не передали', () => {
    // Лучше увидеть {entity} в ответе, чем «undefined topilmadi».
    expect(t('uz', 'error.not_found', {})).toContain('{entity}');
  });
});

describe('parseLang', () => {
  it.each([
    ['uz', 'uz'],
    ['ru', 'ru'],
    ['ru-RU,ru;q=0.9,en;q=0.8', 'ru'],
    ['uz-UZ', 'uz'],
    ['en-US', 'uz'],
    ['', 'uz'],
    [undefined, 'uz'],
  ])('%s → %s', (header, expected) => {
    expect(parseLang(header)).toBe(expected);
  });
});
