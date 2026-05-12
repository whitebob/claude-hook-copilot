// index.js — Frontend entry point
// FIXME: no error boundary implemented
// TODO: add analytics tracking

import { AuthService } from './auth';
import { exportData } from './utils';

class App {
  constructor() {
    this.auth = new AuthService();
    this.initialized = false;
  }

  async init() {
    // FIXME: handle initialization failure
    console.log('App initializing...');
    this.initialized = true;
  }

  async login(username, password) {
    const token = await this.auth.login(username, password);
    console.log('Logged in:', username);
    return token;
  }

  async exportUserData() {
    // TODO: add data filtering options
    const data = await this.loadData();
    return exportData(data);
  }

  async loadData() {
    return [
      { id: 1, name: 'Alice' },
      { id: 2, name: 'Bob' }
    ];
  }
}

export default App;
