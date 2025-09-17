// theme.service.ts
import { Injectable } from '@angular/core';
import { BehaviorSubject } from 'rxjs';

export type ThemeMode = 'light' | 'dark';

@Injectable({ providedIn: 'root' })
export class ThemeService {
  private readonly STORAGE_KEY = 'theme-mode';
  private _mode$ = new BehaviorSubject<ThemeMode>('light');
  mode$ = this._mode$.asObservable();

  init() {
    const saved = (localStorage.getItem(this.STORAGE_KEY) as ThemeMode) || null;
    const prefersDark = window.matchMedia?.('(prefers-color-scheme: dark)').matches;
    const initial: ThemeMode = saved ?? (prefersDark ? 'dark' : 'light');
    this.set(initial);
  }

  set(mode: ThemeMode) {
    document.documentElement.setAttribute('data-bs-theme', mode);
    localStorage.setItem(this.STORAGE_KEY, mode);
    this._mode$.next(mode);
  }

  toggle() {
    this.set(this._mode$.value === 'dark' ? 'light' : 'dark');
  }
}
