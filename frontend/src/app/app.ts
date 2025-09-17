import { Component, signal } from '@angular/core';
import { RouterOutlet } from '@angular/router';
import { Lobby } from './lobby/lobby';
import { Auth } from './auth/auth';
import { Leaderboard } from './leaderboard/leaderboard';

@Component({
  selector: 'app-root',
  imports: [RouterOutlet, Lobby, Auth, Leaderboard],
  templateUrl: './app.html',
  styleUrl: './app.scss'
})
export class App {
  protected readonly title = signal('Frontend');
}
