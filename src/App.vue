<template>
  <div>
    <form class="eppvobhk" :class="{ signing, totpLogin }" @submit.prevent="onSubmit">
      <div class="auth _gaps_m">
        <div v-show="withAvatar" class="avatar" :style="{ backgroundImage: user ? `url('${ user.avatarUrl }')` : null, marginBottom: message ? '1.5em' : null }"></div>
        <MkInfo v-if="message">
          {{ message }}
        </MkInfo>
        <div v-if="!totpLogin" class="normal-signin _gaps_m">
          <MkInput v-model="username" :placeholder="i18n.ts.username" type="text" pattern="^[a-zA-Z0-9_]+$" :spellcheck="false" autocomplete="username" autofocus required data-cy-signin-username @update:model-value="onUsernameChange">
            <template #prefix>@</template>
            <template #suffix>@{{ host }}</template>
          </MkInput>
          <MkInput v-if="!user || user && !user.usePasswordLessLogin" v-model="password" :placeholder="i18n.ts.password" type="password" autocomplete="current-password" :with-password-toggle="true" required data-cy-signin-password>
            <template #prefix><i class="ti ti-lock"></i></template>
            <template #caption><button class="_textButton" type="button" @click="resetPassword">{{ i18n.ts.forgotPassword }}</button></template>
          </MkInput>
          <MkButton type="submit" large primary rounded :disabled="signing" style="margin: 0 auto;">{{ signing ? i18n.ts.loggingIn : i18n.ts.login }}</MkButton>
        </div>
        <div v-if="totpLogin" class="2fa-signin" :class="{ securityKeys: user && user.securityKeys }">
          <div v-if="user && user.securityKeys" class="twofa-group tap-group">
            <p>{{ i18n.ts.tapSecurityKey }}</p>
            <MkButton v-if="!queryingKey" @click="queryKey">
              {{ i18n.ts.retry }}
            </MkButton>
          </div>
          <div v-if="user && user.securityKeys" class="or-hr">
            <p class="or-msg">{{ i18n.ts.or }}</p>
          </div>
          <div class="twofa-group totp-group">
            <p style="margin-bottom:0;">{{ i18n.ts.twoStepAuthentication }}</p>
            <MkInput v-if="user && user.usePasswordLessLogin" v-model="password" type="password" autocomplete="current-password" :with-password-toggle="true" required>
              <template #label>{{ i18n.ts.password }}</template>
              <template #prefix><i class="ti ti-lock"></i></template>
            </MkInput>
            <MkInput v-model="token" type="text" pattern="^[0-9]{6}$" autocomplete="one-time-code" :spellcheck="false" required>
              <template #label>{{ i18n.ts.token }}</template>
              <template #prefix><i class="ti ti-123"></i></template>
            </MkInput>
            <MkButton type="submit" :disabled="signing" large primary rounded style="margin: 0 auto;">{{ signing ? i18n.ts.loggingIn : i18n.ts.login }}</MkButton>
          </div>
        </div>
      </div>
    </form>
  </div>
</template>

<script>


export default {

  data(){
    return {
      i18n: {
        ts: {}
      }
    }
  },
  mounted() {

    const misskeyV13 = document.createElement("script")
    misskeyV13.setAttribute("src", "misskey-v13/app.js")
    misskeyV13.setAttribute("type", "module")
    const misskeyV13Style = document.createElement("link")
    misskeyV13Style.setAttribute("rel", "stylesheet" )
    misskeyV13Style.setAttribute("href", "misskey-v13/init.css")
    document.head.appendChild(misskeyV13)
    document.head.appendChild(misskeyV13Style)
  }
}
</script>


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
