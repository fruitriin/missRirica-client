<template>
<div class="rsqzvsbo">
	<div class="top">
		<div class="shape1"></div>
		<div class="shape2"></div>
		<img src="/client-assets/misskey.svg" class="misskey"/>
		<div class="emojis">
			<MkEmoji :normal="true" :no-style="true" emoji="👍"/>
			<MkEmoji :normal="true" :no-style="true" emoji="❤"/>
			<MkEmoji :normal="true" :no-style="true" emoji="😆"/>
			<MkEmoji :normal="true" :no-style="true" emoji="🎉"/>
			<MkEmoji :normal="true" :no-style="true" emoji="🍮"/>
		</div>
		<div class="main">
			<button class="_button _acrylic menu" @click="showMenu"><i class="ti ti-dots"></i></button>

			<div class="fg">
				<h1 style="pointer-events: none">
					<!-- 背景色によってはロゴが見えなくなるのでとりあえず無効に -->
					<!-- <img class="logo" v-if="meta.logoImageUrl" :src="meta.logoImageUrl"><span v-else class="text">{{ instanceName }}</span> -->
					<span class="text">{{ $ts.ririca.name }}</span>
				</h1>
				<div class="about">
					<!-- eslint-disable-next-line vue/no-v-html -->
					<div class="desc" v-html="$ts.ririca.description"></div>
				</div>
				<div class="action">
					<div>
						<input id="term" v-model="isTerm" type="checkbox"><label for="term">
							{{ $ts.ririca.term }}</label><br>
						<a href="https://riinswork.space/missRirica/privacy/">{{ $ts.ririca.termLink }}</a>
					</div>

					<!--					<MkButton inline rounded gradate data-cy-signup style="margin-right: 12px;" @click="signup()">{{ i18n.ts.signup }}</MkButton>-->
					<MkButton inline rounded data-cy-signin :disabled="!isTerm" @click="signin()">
						{{
							i18n.ts.login
						}}
					</MkButton>

					<MkSelect v-model="lang">
						<template #label>{{ i18n.ts.uiLanguage }}</template>
						<option v-for="x in langs" :key="x[0]" :value="x[0]">{{ x[1] }}</option>
						<template #caption>
							<I18n :src="i18n.ts.i18nInfo" tag="span">
								<template #link>
									<MkLink url="https://crowdin.com/project/misskey">Crowdin</MkLink>
								</template>
							</I18n>
						</template>
					</MkSelect>
				</div>
			</div>
		</div>
	</div>
</div>
</template>

<script lang="ts" setup>
import XSigninDialog from '@/components/MkSigninDialog.vue';
import MkButton from '@/components/MkButton.vue';
import MkSelect from "@/components/MkSelect.vue"
import MkLink from "@/components/MkLink.vue"
import * as os from '@/os';
import { i18n } from '@/i18n';
import { ref, watch } from "vue";
import { miLocalStorage } from "@/local-storage";
import { langs as _langs } from '@/config';
import { unisonReload } from "@/scripts/unison-reload";

const langs = ref(_langs)
const lang = ref(miLocalStorage.getItem('lang'));


let meta = $ref();
let stats = $ref();
let tags = $ref();
let onlineUsersCount = $ref();
let instances = $ref();
let isTerm = $ref()

function signin() {
	os.popup(XSigninDialog, {
		autoSet: true,
	}, {}, 'closed');
}


function showMenu(ev) {
	os.popupMenu([{
		text: i18n.ts.instanceInfo,
		icon: 'ti ti-info-circle',
		action: () => {
			os.pageWindow('/about');
		},
	}, {
		text: i18n.ts.aboutMisskey,
		icon: 'ti ti-info-circle',
		action: () => {
			os.pageWindow('/about-misskey');
		},
	}, null, {
		text: i18n.ts.help,
		icon: 'ti ti-question-circle',
		action: () => {
			window.open('https://misskey-hub.net/help.md', '_blank');
		},
	}], ev.currentTarget ?? ev.target);
}

watch(lang, () => {
  miLocalStorage.setItem('lang', lang.value as string);
  miLocalStorage.removeItem('locale');
});

watch([
  lang,
], async () => {
  await reloadAsk();
});

async function reloadAsk() {
  const { canceled } = await os.confirm({
    type: 'info',
    text: i18n.ts.reloadToApplySetting,
  });
  if (canceled) return;

  unisonReload();
}
</script>

<style lang="scss" scoped>
.rsqzvsbo {
	> .top {
		display: flex;
		text-align: center;
		min-height: 100vh;
		box-sizing: border-box;
		padding: 16px;

		> .bg {
			position: absolute;
			top: 0;
			right: 0;
			width: 80%; // 100%からshapeの幅を引いている
			height: 100%;
		}

		> .tl {
			position: absolute;
			top: 0;
			bottom: 0;
			right: 64px;
			margin: auto;
			width: 500px;
			height: calc(100% - 128px);
			overflow: hidden;
			-webkit-mask-image: linear-gradient(0deg, rgba(0,0,0,0) 0%, rgba(0,0,0,1) 128px, rgba(0,0,0,1) calc(100% - 128px), rgba(0,0,0,0) 100%);
			mask-image: linear-gradient(0deg, rgba(0,0,0,0) 0%, rgba(0,0,0,1) 128px, rgba(0,0,0,1) calc(100% - 128px), rgba(0,0,0,0) 100%);

			@media (max-width: 1200px) {
				display: none;
			}
		}

		> .shape1 {
			position: absolute;
			top: 0;
			left: 0;
			width: 100%;
			height: 100%;
			background: var(--accent);
			clip-path: polygon(0% 0%, 45% 0%, 20% 100%, 0% 100%);
		}
		> .shape2 {
			position: absolute;
			top: 0;
			left: 0;
			width: 100%;
			height: 100%;
			background: var(--accent);
			clip-path: polygon(0% 0%, 25% 0%, 35% 100%, 0% 100%);
			opacity: 0.5;
		}

		> .misskey {
			position: absolute;
			top: 42px;
			left: 42px;
			width: 140px;

			@media (max-width: 450px) {
				width: 130px;
			}
		}

		> .emojis {
			position: absolute;
			bottom: 32px;
			left: 35px;

			> * {
				margin-right: 8px;
			}

			@media (max-width: 1200px) {
				display: none;
			}
		}

		> .main {
			position: relative;
			width: min(480px, 100%);
			margin: auto auto auto 128px;
			background: var(--panel);
			border-radius: var(--radius);
			box-shadow: 0 12px 32px rgb(0 0 0 / 25%);

			@media (max-width: 1200px) {
				margin: auto;
			}

			> .icon {
				width: 85px;
				margin-top: -47px;
				border-radius: 100%;
				vertical-align: bottom;
			}

			> .menu {
				position: absolute;
				top: 16px;
				right: 16px;
				width: 32px;
				height: 32px;
				border-radius: 8px;
				font-size: 18px;
			}

			> .fg {

				> h1 {
					display: block;
					margin: 0;
					padding: 16px 32px 24px 32px;
					font-size: 1.4em;

					> .logo {
						vertical-align: bottom;
						max-height: 120px;
						max-width: min(100%, 300px);
					}
				}

				> .about {
					padding: 0 32px;
				}

				> .action {
					padding: 32px;

					> * {
						line-height: 28px;
					}
				}
			}
		}

		> .federation {
			position: absolute;
			bottom: 16px;
			left: 0;
			right: 0;
			margin: auto;
			background: var(--acrylicPanel);
			-webkit-backdrop-filter: var(--blur, blur(15px));
			backdrop-filter: var(--blur, blur(15px));
			border-radius: 999px;
			overflow: clip;
			width: 800px;
			padding: 8px 0;

			@media (max-width: 900px) {
				display: none;
			}
		}
	}
}
</style>

<style lang="scss" module>
.federationInstance {
	display: inline-flex;
	align-items: center;
	vertical-align: bottom;
	padding: 6px 12px 6px 6px;
	margin: 0 10px 0 0;
	background: var(--panel);
	border-radius: 999px;

	> :global(.icon) {
		display: inline-block;
		width: 20px;
		height: 20px;
		margin-right: 5px;
		border-radius: 999px;
	}
}
</style>
