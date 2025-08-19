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
  constructor(private gs: Service) {}

  ngOnInit() {
    this.refresh();
    setInterval(() => this.refresh(), 2000); // alle 2s aktualisieren
  }

  refresh() {
    this.gs.getServers().subscribe(data => this.servers = data);
  }

  startServer() {
    this.gs.startServer().subscribe(() => this.refresh());
  }
}
