import js from '@eslint/js';
import tseslint from 'typescript-eslint';
import prettier from 'eslint-config-prettier';
import globals from 'globals';

export default tseslint.config(
  { ignores: ['**/node_modules/**', '**/dist/**', 'coverage/**', '.godot/**', 'tools/out/**'] },
  js.configs.recommended,
  ...tseslint.configs.recommended,
  {
    languageOptions: { globals: { ...globals.node } },
    rules: {
      '@typescript-eslint/no-unused-vars': ['error', { argsIgnorePattern: '^_', varsIgnorePattern: '^_' }],
    },
  },
  {
    // Determinism is sacred (spec §5.2): no ambient randomness or clocks in maze generation.
    files: ['server/src/maze/**/*.ts'],
    rules: {
      'no-restricted-properties': [
        'error',
        { object: 'Math', property: 'random', message: 'Use the seeded PRNG (prng.ts); see spec §5.2.' },
        { object: 'Date', property: 'now', message: 'Maze generation must not depend on time.' },
      ],
      'no-restricted-globals': ['error', { name: 'crypto', message: 'Use hash32 from hash.ts.' }],
    },
  },
  prettier,
);
