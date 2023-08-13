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
import { useStorageStore } from "~/store/globalState"
export default defineNuxtComponent({
  setup(){
    const eventBus = useRiricaStateStore()
    const {  userStorage } = useStorageStore()
    return {
      eventBus,
      userStorage
    }
  },
  mounted(){
    if(this.userStorage.user){
      this.$router.replace("/")
    }
  },
  watch: {
    "userStorage.user"(){
      if(this.userStorage.user){
        this.$router.replace("/")
      }
    }
  },
  methods: {
    openLoginDialog(){
      this.eventBus.modalControl.login = true
    }
  }
})
</script>
