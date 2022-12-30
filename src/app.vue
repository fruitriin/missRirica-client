<template>
  <div class="statusbar" />
  <nuxt-page />
</template>

<script lang="ts">
export default {
  name: "App.vue",
};
</script>

<style lang="scss" scoped>
.statusbar {
  height: 20px;
  position: sticky;
  background-color: #ccc;
}
.container {
  width: 100%;
  min-width: 0;
  background: black;
  padding: 24px;
  height: 100%;

  .content {
    overflow-y: auto;
    height: calc(100% - 24px);
    border-radius: 15px;
    background: #fff;
  }
}
</style>

<style>
html,
#__nuxt,
body {
  margin: 0;
  padding: 0;
  font-size: 16px;
  height: 100dvh;
}

:root {
  --header: white;
}
</style>
