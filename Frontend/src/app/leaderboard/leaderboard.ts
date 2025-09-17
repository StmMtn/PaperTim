import { Component, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { HttpClient } from '@angular/common/http';

@Component({
  selector: 'app-leaderboard',
  imports: [CommonModule],
  templateUrl: './leaderboard.html',
  styleUrl: './leaderboard.scss'
})

export class Leaderboard implements OnInit{
  players: any[] = [];
  constructor(private http: HttpClient) {}
  ngOnInit() { this.refresh(); }
  refresh() {
    this.loading = true;
    this.http.get<any[]>('http://localhost:3000/leaderboard')
      .subscribe(p => this.players = p);
    this.lastUpdated = new Date();
    this.loading = false;
  }
lastUpdated?: Date;
loading = false;
}


