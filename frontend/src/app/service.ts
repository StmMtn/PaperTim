import { Injectable } from '@angular/core';
import { HttpClient } from '@angular/common/http';

@Injectable({providedIn: 'root'})
export class Service {
    constructor(private http: HttpClient) {}

  getServers() {
    return this.http.get<any[]>('/api/servers');
  }

  startServer() {
    return this.http.post('/api/servers', {});
  }
}
