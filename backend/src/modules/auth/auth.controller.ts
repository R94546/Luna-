import { Body, Controller, Get, HttpCode, Patch, Post, Req, UsePipes } from '@nestjs/common';
import { Throttle } from '@nestjs/throttler';
import { Request } from 'express';
import { AuthUser, CurrentUser } from '../../common/decorators/current-user.decorator';
import { Public } from '../../common/decorators/public.decorator';
import { ZodValidationPipe } from '../../common/pipes/zod-validation.pipe';
import { AuthService } from './auth.service';
import {
  ChangePasswordDto,
  LoginDto,
  RefreshDto,
  RegisterDto,
  changePasswordSchema,
  loginSchema,
  refreshSchema,
  registerSchema,
} from './dto/auth.dto';

@Controller('auth')
export class AuthController {
  constructor(private readonly auth: AuthService) {}

  @Public()
  @Post('register')
  @UsePipes(new ZodValidationPipe(registerSchema))
  register(@Body() dto: RegisterDto, @Req() req: Request) {
    return this.auth.register(dto, req.headers['user-agent']);
  }

  /**
   * 5 попыток за 15 минут. Без ограничения пароль из шести цифр
   * подбирается за считанные минуты.
   */
  @Public()
  @Post('login')
  @HttpCode(200)
  @Throttle({ default: { limit: 5, ttl: 900_000 } })
  @UsePipes(new ZodValidationPipe(loginSchema))
  login(@Body() dto: LoginDto, @Req() req: Request) {
    return this.auth.login(dto, req.headers['user-agent']);
  }

  @Public()
  @Post('refresh')
  @HttpCode(200)
  @UsePipes(new ZodValidationPipe(refreshSchema))
  refresh(@Body() dto: RefreshDto, @Req() req: Request) {
    return this.auth.refresh(dto.refreshToken, req.headers['user-agent']);
  }

  @Post('logout')
  @HttpCode(204)
  @UsePipes(new ZodValidationPipe(refreshSchema))
  async logout(@Body() dto: RefreshDto): Promise<void> {
    await this.auth.logout(dto.refreshToken);
  }

  @Get('me')
  me(@CurrentUser() user: AuthUser) {
    return this.auth.me(user.userId);
  }

  @Patch('password')
  @HttpCode(204)
  @UsePipes(new ZodValidationPipe(changePasswordSchema))
  async changePassword(
    @CurrentUser() user: AuthUser,
    @Body() dto: ChangePasswordDto,
  ): Promise<void> {
    await this.auth.changePassword(user.userId, dto);
  }
}
