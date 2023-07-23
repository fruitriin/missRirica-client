import { defineStore } from 'pinia'

// You can name the return value of `defineStore()` anything you want,
// but it's best to use the name of the store and surround it with `use`
// and `Store` (e.g. `useUserStore`, `useCartStore`, `useProductStore`)
// the first argument is a unique id of the store across your application

type UserId = string
/**
 * ユーザーごとに発生する揮発性のステート
 */
type UserState = {}
type UsersState = Record<UserId, UserState>
import { useStorage } from '@vueuse/core'

/**
 * LocalStorageに保存するユーザー固有データ
 */
type UserStorage = {  }
type UserStorages = Record<UserId, UserStorage>

/**
 * ローカルストレージで保存するデータ
 * applicationStorageはMissRirica
 *
 *
 */
export const useStorageStore = () => {

  const applicationStorage = useStorage(
    "applicationStorage", {}
  )
  const usersStorage: UserStorage = useStorage(
    "usersStorage", {} as UserStorages
  )
  return {
    applicationStorage,
    usersStorage
  }
}


export const useStateStore = defineStore('state', {
  state: () => {
    return {
      users: {} as UsersState
    }
  }
})

const riricaState = {
  modalControl: {
    login: false,
    something: true
  }
} as const

export const useRiricaStateStore = defineStore("riricaState", {
  state: () => riricaState
})

export type ModalControlNames = keyof typeof riricaState.modalControl
