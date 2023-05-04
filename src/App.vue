<template>
  <div v-if="!loggedIn" class="ui middle aligned center aligned grid">
    <h1 class="ui teal image">MissRirica</h1>
    <form class="ui large form" @submit.prevent>

      <div>
        MissRiricaはMisskeyクライアントです。
      </div>
      <div class="ui stacked segment">
        <div class="field">
          <label class="ui left icon input">
            <input v-model="serverHost" placeholder="https://misskey.example.com/"/>
          </label>
        </div>
        <div class="field">
          <label class="ui left icon input">
            <input v-model="userName" placeholder="アカウント名"/>
          </label>
        </div>
        <div class="field">
          <label class="ui left icon input">
            <input v-model="accessToken" type="password" placeholder="アクセストークン"/>
          </label>
        </div>
        <div class="field">
          <input type="checkbox"><a href="https://riinswork.space/missRirica/privacy/">MissRirica 利用規約 &
          プライバシーポリシー</a>
        </div>
        <button @click="signIn" class="ui fluid large teal submit button">ろぐいん！</button>
        <pre>{{ url }}</pre>
        <pre>{{ debug }}</pre>
        <img src="@@/assets/ririca.png">
      </div>
    </form>

  </div>
</template>

<script lang="ts">
import {api as misskeyApi} from 'misskey-js';
import { useStorage } from '@vueuse/core'
import { defineComponent } from "vue";

export default defineComponent({
  setup(){
    const account = useStorage('account', {})
    const accounts = useStorage('accounts', [])

    function addAccount(id: string, token : string, instanceUrl :string) {
      console.log(instanceUrl)
      if (!accounts.value.some((x) => x.id === id)) {
        accounts.value.push({ id, token, instanceUrl})
        console.log(accounts.value)
      }
      account.value = {id, token, instanceUrl}
    }

    return {
      account,
      accounts ,
      addAccount
    }
  },
  mounted() {
    if (this.account.instanceUrl) this.activateMisskeyV13()
  },
  data() {
    return {
      i18n: {
        ts: {}
      },
      serverHost: "",
      userName: "",
      accessToken: "",
      account: {},
      loggedIn: false,
      debug: {},
    }
  },
  computed: {
    url() {
      return "https://" + this.serverHost.replace("https://", "").replace("http://", "").split("/")[0];
    }
  },
  methods: {
    signIn() {
      const api = new misskeyApi.APIClient({
        origin: this.url,
        credential: this.accessToken,
      });

      api.request("i").then((res) => {
        if(res.error) {
          this.debug = res
          return
        }
        this.account = res

        this.addAccount(res.id, this.accessToken, this.url)
        this.activateMisskeyV13()
      }).catch((e) => {
        this.debug = e
      })
    },

    activateMisskeyV13() {

      const misskeyV13 = document.createElement("script")
      misskeyV13.setAttribute("src", "misskey-v13/app.js")
      misskeyV13.setAttribute("type", "module")
      const misskeyV13Style = document.createElement("link")
      misskeyV13Style.setAttribute("rel", "stylesheet")
      misskeyV13Style.setAttribute("href", "misskey-v13/init.css")
      document.head.appendChild(misskeyV13)
      document.head.appendChild(misskeyV13Style)
      this.loggedIn = true
    }
  },
})
</script>

<style lang="scss">
@import 'semantic-ui-css/semantic.min.css';
</style>

<style lang="scss" scoped>


.eppvobhk {
  > .auth {
    > .avatar {
      margin: 0 auto 0 auto;
      width: 64px;
      height: 64px;
      background: #ddd;
      background-position: center;
      background-size: cover;
      border-radius: 100%;
    }
  }
}
</style>
