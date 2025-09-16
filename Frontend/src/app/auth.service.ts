import { Injectable } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { tap } from 'rxjs/operators';

@Injectable({ providedIn: 'root' })
export class AuthService {
  private base = 'http://localhost:3000';
  private token?: string;
  user?: any;

  constructor(private http: HttpClient) {
    this.token = localStorage.getItem('token') ?? undefined;
  }

  register(username: string, password: string) {
    return this.http.post<{ token: string; user: any }>(`${this.base}/auth/register`, { username, password })
      .pipe(tap(res => { this._saveToken(res.token, res.user); }));
  }

  login(username: string, password: string) {
    return this.http.post<{ token: string; user: any }>(`${this.base}/auth/login`, { username, password })
      .pipe(tap(res => { this._saveToken(res.token, res.user); }));
  }

  logout() {
    localStorage.removeItem('token');
    this.token = undefined;
    this.user = undefined;
  }

  getToken() { return this.token; }

  private _saveToken(token: string, user: any) {
    this.token = token;
    this.user = user;
    localStorage.setItem('token', token);
  }
}
