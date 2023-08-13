<template>
  <div>
    <h1>MissRirica</h1>

    <p>アプリケーションプライバシーポリシー</p>
    <p>利用規約</p>

    <button @click="openLoginDialog">ログイン</button>

    {{ usersStoragesModel.state.value }}
  </div>
</template>
<script lang="ts">
import { useRiricaStateStore } from "~/store/globalState";
import { useStorageStore } from "~/store/globalState"
export default defineNuxtComponent({
  setup(){
    const eventBus = useRiricaStateStore()
    const { usersStoragesModel } = useStorageStore()
    return {
      eventBus,
      usersStoragesModel
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
