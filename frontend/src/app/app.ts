import { Component, signal,OnInit } from '@angular/core';
import { RouterOutlet } from '@angular/router';
import { Lobby } from './lobby/lobby';
import { Auth } from './auth/auth';
import { Leaderboard } from './leaderboard/leaderboard';
import { ThemeService } from './theme';

@Component({
  selector: 'app-root',
  imports: [RouterOutlet, Lobby, Auth, Leaderboard],
  templateUrl: './app.html',
  styleUrl: './app.scss'
})
export class App implements OnInit {
  protected readonly title = signal('Frontend');
  constructor(private theme: ThemeService) {}
  ngOnInit() { this.theme.init(); }
}
