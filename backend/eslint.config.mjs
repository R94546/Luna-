import js from '@eslint/js';
import tsPlugin from '@typescript-eslint/eslint-plugin';
import tsParser from '@typescript-eslint/parser';
import globals from 'globals';

/**
 * Flat-config для ESLint 9.
 *
 * Правила намеренно без проверки типов (`recommended`, а не
 * `recommended-type-checked`): типы уже проверяет `tsc --noEmit` на всём
 * проекте, включая test/ и prisma/, которые в tsconfig исключены из сборки.
 * Дублировать это в линтере — значит держать второй tsconfig ради тех же
 * ошибок и платить временем на каждом запуске.
 */
export default [
  {
    ignores: ['dist/**', 'node_modules/**', 'prisma/generated/**', '*.config.mjs'],
  },
  js.configs.recommended,
  {
    files: ['**/*.ts'],
    languageOptions: {
      parser: tsParser,
      parserOptions: {
        ecmaVersion: 2022,
        sourceType: 'module',
      },
      globals: {
        ...globals.node,
      },
    },
    plugins: {
      '@typescript-eslint': tsPlugin,
    },
    rules: {
      ...tsPlugin.configs.recommended.rules,

      // Аргументы с префиксом _ — сознательно неиспользуемые: middleware
      // Express и обработчики grammY получают фиксированную сигнатуру.
      '@typescript-eslint/no-unused-vars': [
        'error',
        { argsIgnorePattern: '^_', varsIgnorePattern: '^_' },
      ],

      // Nest внедряет зависимости через конструктор, пустых интерфейсов
      // и явных any в коде быть не должно.
      '@typescript-eslint/no-explicit-any': 'error',
      '@typescript-eslint/no-non-null-assertion': 'error',

      // console вместо Logger теряет контекст запроса и уровень.
      'no-console': ['warn', { allow: ['warn', 'error'] }],
      eqeqeq: ['error', 'smart'],
      'no-return-await': 'error',
    },
  },
  {
    // Ручные сценарии проверок — обычные скрипты, им console нужен.
    files: ['test/**/*.ts', 'prisma/seed.ts'],
    rules: {
      'no-console': 'off',
    },
  },
  {
    // describe/it/expect приходят из окружения jest, а не из импортов.
    files: ['**/*.spec.ts'],
    languageOptions: {
      globals: {
        ...globals.jest,
      },
    },
  },
];
