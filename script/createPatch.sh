#bin/bash

# Riricaのベースとなるコミットと、とRiricaの原稿コードの差分をとる
# といいつつ今 master最新をひっぱってきてる

cd misskeyV13
git reset origin/master --hard
cd ../
rm -rf migrateWork
cp -r misskeyV13/packages/frontend/src migrateWork
eslint --fix src migrateWork
prettier -w migrateWork
prettier -w src
diff -ru migrateWork src > mypatch.patch
# rm -rf migrateWork

sh script/createLocal.sh