echo 'Install NVM & nodejs & npm'
echo '#################################################################'
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.5/install.sh | bash
source ~/.bashrc
nvm ls-remote
nvm install v20.9.0
nvm ls
nvm use v20.9.0
sudo chown "$USER":"$USER" ~/.npm -R
sudo chown "$USER":"$USER" ~/.nvm -R
npm i -g yarn prettier eslint nodemon dotenv

npm i
echo '#################################################################'
