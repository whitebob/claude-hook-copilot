// auth.ts — Authentication service with TODO and FIXME markers
export class AuthService {
  private tokens: Map<string, string> = new Map();

  // TODO: implement refresh token rotation
  async login(username: string, password: string): Promise<string> {
    // FIXME: password should be hashed before comparison
    const token = Buffer.from(`${username}:${password}`).toString('base64');
    this.tokens.set(username, token);
    return token;
  }

  async validate(token: string): Promise<boolean> {
    // TODO: add token expiry check
    return Array.from(this.tokens.values()).includes(token);
  }

  // FIXME: logout doesn't invalidate all sessions
  async logout(username: string): Promise<void> {
    this.tokens.delete(username);
  }

  // TODO: add OAuth2 support for enterprise customers
  async refreshToken(username: string): Promise<string | null> {
    const existing = this.tokens.get(username);
    if (!existing) return null;
    const newToken = Buffer.from(`${username}:refresh:${Date.now()}`).toString('base64');
    this.tokens.set(username, newToken);
    return newToken;
  }
}
