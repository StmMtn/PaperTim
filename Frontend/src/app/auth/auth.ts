import { Component } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { AuthService } from '../auth.service';

@Component({
  selector: 'app-auth',
  imports: [CommonModule, FormsModule],
  templateUrl: './auth.html',
  styleUrl: './auth.scss'
})
export class Auth {
  username = '';
  password = '';

  constructor(public auth: AuthService) {}

  login() {
    this.auth.login(this.username, this.password).subscribe();
  }

  register() {
    this.auth.register(this.username, this.password).subscribe();
  }

  logout() {
    this.auth.logout();
  }
}
