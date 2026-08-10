import js from '@eslint/js';

export default [
  { ignores: ['node_modules/**', 'dist/**', 'artifacts/**', '.hermes/**', '_dev_tools/**'] },
  js.configs.recommended,
  {
    files: ['src/**/*.js', 'scripts/**/*.mjs', 'tests/**/*.js'],
    languageOptions: {
      ecmaVersion: 2023,
      sourceType: 'module',
      globals: {
        browser: 'readonly', chrome: 'readonly', document: 'readonly', window: 'readonly',
        navigator: 'readonly', location: 'readonly', fetch: 'readonly', Blob: 'readonly', Response: 'readonly',
        URL: 'readonly', TextEncoder: 'readonly', console: 'readonly', setTimeout: 'readonly',
        clearTimeout: 'readonly', process: 'readonly', Buffer: 'readonly'
      }
    },
    rules: { 'no-unused-vars': ['error', { argsIgnorePattern: '^_' }] }
  }
];
