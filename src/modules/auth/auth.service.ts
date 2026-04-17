import { Injectable } from '@nestjs/common';
import * as bcrypt from 'bcrypt';
import { JwtService } from '@nestjs/jwt';

type User = {
  id: number;
  email: string;
  password: string;
};

@Injectable()
export class AuthService {
  private users: User[] = [];

  constructor(private jwtService: JwtService) {}

  async register(email: string, password: string) {
    const hashedPassword = await bcrypt.hash(password, 10);

    const user: User = {
      id: Date.now(),
      email,
      password: hashedPassword,
    };

    this.users.push(user);

    return {
      message: 'User registered successfully',
    };
  }

  async login(email: string, password: string) {
    const user = this.users.find(u => u.email === email);

    if (!user) {
      throw new Error('User not found');
    }

    const isPasswordValid = await bcrypt.compare(password, user.password);

    if (!isPasswordValid) {
      throw new Error('Invalid credentials');
    }

    const payload = { userId: user.id, email: user.email };

    return {
      access_token: this.jwtService.sign(payload),
    };
  }
}