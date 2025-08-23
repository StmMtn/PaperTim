import { Component, OnInit } from '@angular/core';
import { Service } from '../service';
import { CommonModule } from '@angular/common';

@Component({
  imports: [CommonModule],
  templateUrl: './lobby.html',
  selector: 'app-lobby',
  standalone: true,
})
export class Lobby implements OnInit {
  servers: any[] = [];
  startingServers: any[] = [];
  devServerPort = "8443";
  maxPlayers = 10;

  constructor(private gs: Service) {}

  ngOnInit() {
    this.refresh();
    setInterval(() => this.refresh(), 2000);
  }

  refresh() {
    this.gs.getServers().subscribe(newServers => {
      newServers = newServers || [];

      // Remove startingServers that now exist in newServers (match by port or id)
      this.startingServers = this.startingServers.filter(temp =>
        !newServers.some(s => s.port === temp.port)
      );

      this.servers = [...newServers];
      console.log('Servers:', this.servers);

      // Sortierung: Dev-Server oben, volle Server unten
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
    // füge temporären Server hinzu
    this.startingServers.push({ tempId: 'temp_' + Date.now() });

    // Starte den Server über Service
    this.gs.startServer().subscribe({
      next: () => {
        // Direkt nach erfolgreichem Start: temporäre Server entfernen
        this.startingServers = [];
        this.refresh();
      },
      error: () => {
        // Bei Fehler ebenfalls temporäre Server entfernen
        this.startingServers = [];
      }
    });
  }

  stopServer(id: string) {
    this.gs.stopServer(id).subscribe(() => this.refresh());
  }

  isFull(server: any): boolean {
    return server.players >= this.maxPlayers;
  }
}
