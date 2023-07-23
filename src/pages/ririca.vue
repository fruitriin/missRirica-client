<template>
  <div>
    <h1>MissRirica</h1>

    <p>アプリケーションプライバシーポリシー</p>
    <p>利用規約</p>

    <button @click="openLoginDialog">ログイン</button>
  </div>
</template>
<script lang="ts">
import { useRiricaStateStore } from "~/store/globalState";

export default defineNuxtComponent({
  setup(){
    const eventBus = useRiricaStateStore()
    return {
      eventBus
    }
  },
  data(){
    return {}
  },
  methods: {
    openLoginDialog(){
      console.log( this.eventBus.modalControl)
      this.eventBus.modalControl.login = true
      console.log( this.eventBus.modalControl)
    }
  }
})
</script>
