export default {
  extends: ["eslint:recommended", "plugin:vue/vue3-recommended", "prettier"],
  parser: "vue-eslint-parser",
  parserOptions: {
    parser: "@typescript-eslint/parser",
    ecmaVersion: 2020,
    sourceType: "module",
  },
  rules: {
    //  https://eslint.org/docs/latest/rules/function-call-argument-newline
    "function-call-argument-newline": "consist", // Enforce line breaks between arguments of a function call
    "no-debugger": 0,
    "no-console": 0,
    "vue/singleline-html-element-content-newline": 0,
    "vue/html-closing-bracket-newline": 0,
    "vue/html-indent": 0,
    "eol-last": "always",
    "comma-dangle": [
      "error",
      {
        arrays: "always-multiline",
        objects: "always-multiline",
        imports: "always-multiline",
        exports: "always-multiline",
        functions: "never",
      },
    ],
    "no-unused-vars": [
      "never",
      {
        argsIgnorePattern: "^_",
      },
    ],
    "no-undef": 0,
    "vue/no-v-html": 0,
    "vue/max-attributes-per-line": 0,
    "vue/html-self-closing": [
      "error",
      {
        html: {
          void: "always",
        },
      },
    ],
  },
};
