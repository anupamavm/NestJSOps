import { Injectable, UnauthorizedException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import * as bcrypt from 'bcrypt';
import { PrismaService } from '../../prisma/prisma.service';

@Injectable()
export class AuthService {
  constructor(
    private prisma: PrismaService,
    private jwt: JwtService,
  ) {}

  async register(email: string, password: string) {
    const hashed = await bcrypt.hash(password, 10);

    await this.prisma.user.create({
      data: {
        email,
        password: hashed,
      },
    });

    return { message: 'User created' };
  }

  async login(email: string, password: string) {
    const user = await this.prisma.user.findUnique({ where: { email } });

    if (!user) throw new UnauthorizedException('Invalid credentials');

    const valid = await bcrypt.compare(password, user.password);
    if (!valid) throw new UnauthorizedException('Invalid credentials');

    const accessToken = this.jwt.sign(
      { sub: user.id, email: user.email },
      { expiresIn: '15m' },
    );

    const refreshToken = this.jwt.sign({ sub: user.id }, { expiresIn: '7d' });

    await this.prisma.user.update({
      where: { id: user.id },
      data: { refreshToken },
    });

    return { accessToken, refreshToken };
  }

  async logout(userId: string) {
    await this.prisma.user.update({
      where: { id: userId },
      data: { refreshToken: null },
    });

    return { message: 'Logged out' };
  }

  async refresh(refreshToken: string) {
    console.log('🔁 REFRESH CALLED');
    console.log('Incoming refreshToken:', refreshToken);

    if (!refreshToken) {
      console.log('❌ No refresh token provided');
      throw new UnauthorizedException('No refresh token provided');
    }

    let payload: any;

    try {
      payload = this.jwt.verify(refreshToken);
      console.log('✅ JWT verified payload:', payload);
    } catch (err) {
      console.log('❌ JWT verification failed:', err.message);
      throw new UnauthorizedException('Invalid refresh token');
    }

    const userId = payload.sub;
    console.log('👤 Extracted userId:', userId);

    const user = await this.prisma.user.findUnique({
      where: { id: userId },
    });

    console.log('🧾 User from DB:', {
      found: !!user,
      hasRefreshToken: !!user?.refreshToken,
    });

    if (!user || !user.refreshToken) {
      console.log('❌ User missing or no refresh token in DB');
      throw new UnauthorizedException('Access denied');
    }

    const isValid = await bcrypt.compare(refreshToken, user.refreshToken);

    console.log('🔐 bcrypt compare result:', isValid);

    if (!isValid) {
      console.log('❌ Refresh token mismatch (bcrypt failed)');
      throw new UnauthorizedException('Invalid refresh token');
    }

    const newPayload = {
      sub: user.id,
      email: user.email,
    };

    const newAccessToken = this.jwt.sign(newPayload, {
      expiresIn: '15m',
    });

    const newRefreshToken = this.jwt.sign(newPayload, {
      expiresIn: '7d',
    });

    const hashed = await bcrypt.hash(newRefreshToken, 10);

    await this.prisma.user.update({
      where: { id: user.id },
      data: {
        refreshToken: hashed,
      },
    });

    console.log('🔄 Tokens rotated successfully');

    return {
      accessToken: newAccessToken,
      refreshToken: newRefreshToken,
    };
  }
}
