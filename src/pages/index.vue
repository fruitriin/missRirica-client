<script lang="ts">
import { useStateStore, useStorageStore } from "~/store/globalState";


export default defineNuxtComponent({
  setup(){
    const {userStorage} = useStorageStore()
    const { $state, } = useStateStore()

    return {
      state: $state,
      userStorage
    }
  },
  mounted(){
    if(!this.userStorage.user){
      this.$router.replace("/login")
    }
  },
  data(){
    return {
      debug: {}
    }
  },
  methods: {
    async getTimeline(){
      const res = await this.userStorage.request("notes/hybrid-timeline" )
      this.state.users.timeline = res
    },
    async registerNotification(){
      const res = await this.userStorage.request("sw/register", {
        auth: "BggqhkjOPQMBAQ==",
        publickey: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        endpoint: "https://ufxywtqkcanqavmilojl.supabase.co/functions/v1/sendNotification",
        sendReadMessage: true,
      })
      this.debug = res
    },
    async unregister(){
      const res = await this.userStorage.request("sw/unregister", {
        endpoint: "https://ufxywtqkcanqavmilojl.supabase.co/functions/v1/sendNotification"
      })
      this.debug = res
    }

  }
})

</script>

<template>
  <div>
    yehhhh
    <button @click="registerNotification">Notification ON</button> <button @click="unregister">unregister</button>
    {{ debug }}

    <button @click="getTimeline">timeline</button>

    <div v-for="item in state.users.timeline">
      {{ item.text }}
    </div>
  </div>
</template>

<style lang="scss">

</style>
