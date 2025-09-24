import { Component, OnInit } from '@angular/core';
import { Service } from '../service';
import { CommonModule } from '@angular/common';
import { AuthService } from '../auth.service';
import { ThemeService } from '../theme';

@Component({
  imports: [CommonModule],
  templateUrl: './lobby.html',
  selector: 'app-lobby',
  standalone: true,
})
export class Lobby implements OnInit {
  servers: any[] = [];
  startingServers: any[] = [];
  devServerPort = '8443';
  maxPlayers = 4;

  constructor(
    private gs: Service,
    public auth: AuthService,
    public theme: ThemeService
  ) {}

  ngOnInit() {
    this.refresh();
    setInterval(() => this.refresh(), 2000);
  }

  get isLoggedIn(): boolean {
    return !!this.auth.user && !!this.auth.getToken();
  }

  private encodeName(name?: string): string {
    return name ? encodeURIComponent(name) : '';
  }

  buildJoinHref(server: any): string | null {
    const token = this.auth.getToken();
    if (!token) return null; // nicht eingeloggt -> kein Link
    const name = this.encodeName(this.auth.user?.username);
    const qs = new URLSearchParams({ token, name }).toString();
    return `http://localhost:${server.port}?${qs}`;
  }

  refresh() {
    this.gs.getServers().subscribe((newServers: any[] = []) => {
      this.startingServers = this.startingServers.filter(
        (temp) => !newServers.some((s) => s.port === temp.port)
      );
      this.servers = [...newServers];

      this.servers.sort((a, b) => {
        if (a.port === this.devServerPort) return -1;
        if (b.port === this.devServerPort) return 1;
        if ((a.players || 0) >= this.maxPlayers) return 1;
        if ((b.players || 0) >= this.maxPlayers) return -1;
        return 0;
      });
    });
  }

  startServer() {
    this.startingServers.push({ tempId: 'temp_' + Date.now() });
    this.gs.startServer().subscribe({
      next: () => {
        this.startingServers = [];
        this.refresh();
      },
      error: () => {
        this.startingServers = [];
      },
    });
  }

  stopServer(id: string) {
    this.gs.stopServer(id).subscribe(() => this.refresh());
  }

  isFull(server: any): boolean {
    return (server.players || 0) >= this.maxPlayers;
  }
}
