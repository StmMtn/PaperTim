import { Injectable } from '@angular/core';
import { HttpClient } from '@angular/common/http';

@Injectable({
  providedIn: 'root'
})

export class Service {
  private baseUrl = 'http://localhost:3000'
  constructor(private http: HttpClient) {}

  getServers() {
    return this.http.get<any[]>(`${this.baseUrl}/servers`);
  }

  startServer() {
    return this.http.post(`${this.baseUrl}/servers`, {});
  }
}
