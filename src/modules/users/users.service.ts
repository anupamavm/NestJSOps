import { Injectable } from '@nestjs/common';

@Injectable()
export class UsersService {
  private users = [
    { id: 1, name: 'Anupama' },
    { id: 2, name: 'John' },
  ];

  findAll() {
    return this.users;
  }
}